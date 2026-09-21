//! A renderer.
//!
//! The renderer is used to queue up rendering commands. Once all commands for a
//! frame have been queued, call `render` to render them to a window.

const builtin = @import("builtin");
const math = @import("../math.zig");
const sdl = @import("sdl");
const std = @import("std");

pub const Spritesheet = @import("Spritesheet.zig");

/// A queue of commands to be performed during rendering.
command_queue: CommandQueue,
/// A queue of vertices to be uploaded to the GPU.
vertex_queue: std.ArrayList(Vertex),
/// The spritesheet used by the renderer.
spritesheet: Spritesheet,
/// A multiplier applied to rendering coordinates.
scale: math.Vec2(f32) = .splat(1),

/// The SDL GPU context.
_gpu_device: *sdl.SDL_GPUDevice,
/// The SDL GPU graphics pipeline used to render.
_gpu_pipeline: *sdl.SDL_GPUGraphicsPipeline,
/// An SDL GPU sampler used to sample vertex textures.
_gpu_sampler: *sdl.SDL_GPUSampler,
/// A buffer used to upload vertices to the GPU.
///
/// The buffer's capacity is assumed to match that of `vertex_queue`.
_gpu_transfer_buffer: *sdl.SDL_GPUTransferBuffer,
/// A buffer of vertices in GPU memory.
///
/// The buffer's capacity is assumed to match that of `vertex_queue`.
_gpu_buffer: *sdl.SDL_GPUBuffer,

const Renderer = @This();

/// The texture format used by rendering targets.
const target_texture_format = sdl.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM;

/// Returns a new renderer.
///
/// The renderer is owned by the caller and must be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator) !Renderer {
    const gpu_device = sdl.SDL_CreateGPUDevice(sdl.SDL_GPU_SHADERFORMAT_MSL, builtin.mode == .Debug, null) orelse
        return error.Sdl;
    errdefer sdl.SDL_DestroyGPUDevice(gpu_device);

    var command_queue: CommandQueue = .{ ._list = try .initCapacity(gpa, 512) };
    errdefer command_queue._list.deinit(gpa);

    var vertex_queue: std.ArrayList(Vertex) = try .initCapacity(gpa, 512);
    errdefer vertex_queue.deinit(gpa);

    var io_single_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_single_threaded.io();

    var spritesheet = try Spritesheet.init(io, gpa, gpu_device);
    errdefer spritesheet.deinit(gpu_device);

    const file_buf = try gpa.alloc(u8, 1024);
    defer gpa.free(file_buf);

    const vert_shader_code = try std.Io.Dir.cwd().readFile(io, "res/vert.msl", file_buf);
    const vert_shader = sdl.SDL_CreateGPUShader(gpu_device, &.{
        .code_size = vert_shader_code.len,
        .code = vert_shader_code.ptr,
        .entrypoint = "VertMain",
        .format = sdl.SDL_GPU_SHADERFORMAT_MSL,
        .stage = sdl.SDL_GPU_SHADERSTAGE_VERTEX,
    }) orelse
        return error.Sdl;
    defer sdl.SDL_ReleaseGPUShader(gpu_device, vert_shader);

    const frag_shader_code = try std.Io.Dir.cwd().readFile(io, "res/frag.msl", file_buf);
    const frag_shader = sdl.SDL_CreateGPUShader(gpu_device, &.{
        .code_size = frag_shader_code.len,
        .code = frag_shader_code.ptr,
        .entrypoint = "FragMain",
        .format = sdl.SDL_GPU_SHADERFORMAT_MSL,
        .stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
        .num_samplers = 1,
        .num_uniform_buffers = 1,
    }) orelse
        return error.Sdl;
    defer sdl.SDL_ReleaseGPUShader(gpu_device, frag_shader);

    const gpu_pipeline = sdl.SDL_CreateGPUGraphicsPipeline(gpu_device, &.{
        .vertex_shader = vert_shader,
        .fragment_shader = frag_shader,
        .vertex_input_state = .{
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = &.{
                .slot = 0,
                .pitch = @sizeOf(Vertex),
                .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            },
            .num_vertex_attributes = 2,
            .vertex_attributes = &[_]sdl.SDL_GPUVertexAttribute{
                .{ .buffer_slot = 0, .location = 0, .offset = 0, .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2 },
                .{ .buffer_slot = 0, .location = 1, .offset = @sizeOf(f32) * 2, .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2 },
            },
        },
        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &.{
                .format = target_texture_format,
                .blend_state = .{
                    .enable_blend = true,
                    .src_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                    .dst_color_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                    .color_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
                    .src_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                    .dst_alpha_blendfactor = sdl.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                    .alpha_blend_op = sdl.SDL_GPU_BLENDOP_ADD,
                },
            },
        },
    }) orelse
        return error.Sdl;
    errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(gpu_device, gpu_pipeline);

    const gpu_sampler = sdl.SDL_CreateGPUSampler(gpu_device, &.{}) orelse
        return error.Sdl;
    errdefer sdl.SDL_ReleaseGPUSampler(gpu_device, gpu_sampler);

    const gpu_buffer = sdl.SDL_CreateGPUBuffer(gpu_device, &.{
        .usage = sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
        .size = @intCast(vertex_queue.capacity * @sizeOf(Vertex)),
    }) orelse
        return error.Sdl;
    errdefer sdl.SDL_ReleaseGPUBuffer(gpu_device, gpu_buffer);

    const gpu_transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(gpu_device, &.{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(vertex_queue.capacity * @sizeOf(Vertex)),
    }) orelse
        return error.Sdl;
    errdefer sdl.SDL_ReleaseGPUTransferBuffer(gpu_device, gpu_transfer_buffer);

    return .{
        .vertex_queue = vertex_queue,
        .command_queue = command_queue,
        .spritesheet = spritesheet,
        ._gpu_device = gpu_device,
        ._gpu_pipeline = gpu_pipeline,
        ._gpu_sampler = gpu_sampler,
        ._gpu_buffer = gpu_buffer,
        ._gpu_transfer_buffer = gpu_transfer_buffer,
    };
}

/// Frees the renderer.
///
/// The renderer should not be used after calling this function.
pub fn deinit(self: *Renderer, gpa: std.mem.Allocator) void {
    self.command_queue._list.deinit(gpa);
    self.vertex_queue.deinit(gpa);
    self.spritesheet.deinit(self._gpu_device);
    sdl.SDL_ReleaseGPUTransferBuffer(self._gpu_device, self._gpu_transfer_buffer);
    sdl.SDL_ReleaseGPUBuffer(self._gpu_device, self._gpu_buffer);
    sdl.SDL_ReleaseGPUSampler(self._gpu_device, self._gpu_sampler);
    sdl.SDL_ReleaseGPUGraphicsPipeline(self._gpu_device, self._gpu_pipeline);
    sdl.SDL_DestroyGPUDevice(self._gpu_device);
    self.* = undefined;
}

// Drawing

/// Cancels all pending draw operations.
pub fn clear(self: *Renderer) void {
    self.vertex_queue.clearRetainingCapacity();
    self.command_queue.clear();
}

/// Draws the given region of the spritesheet to the given rectangle.
pub fn drawRegion(
    self: *Renderer,
    src: math.Rect(u8),
    dst: math.Rect(f32),
) !void {
    const corners = dst.corners();

    const rect_vertices: [4]Vertex = .{
        .construct(self.mapPos(corners.tl), .{ .x = @as(f32, src.x) / Spritesheet.width, .y = @as(f32, src.y) / Spritesheet.height }),
        .construct(self.mapPos(corners.tr), .{ .x = @as(f32, src.x + src.w) / Spritesheet.width, .y = @as(f32, src.y) / Spritesheet.height }),
        .construct(self.mapPos(corners.bl), .{ .x = @as(f32, src.x) / Spritesheet.width, .y = @as(f32, src.y + src.h) / Spritesheet.height }),
        .construct(self.mapPos(corners.br), .{ .x = @as(f32, src.x + src.w) / Spritesheet.width, .y = @as(f32, src.y + src.h) / Spritesheet.height }),
    };

    try self.vertex_queue.appendSliceBounded(&.{
        rect_vertices[0],
        rect_vertices[2],
        rect_vertices[3],
        rect_vertices[0],
        rect_vertices[3],
        rect_vertices[1],
    });
    try self.command_queue.drawVertices(6);
}

/// Draws the given region of the spritesheet to the given rectangle, as a nine-patch.
pub fn drawRegion9Patch(
    self: *Renderer,
    src: math.Rect(u8),
    border: math.Sides(u8),
    dst: math.Rect(f32),
) !void {
    try self.drawRegion(
        .{ .x = src.x, .y = src.y, .w = border.left, .h = border.top },
        .{ .x = dst.x, .y = dst.y, .w = border.left, .h = border.top },
    );
    try self.drawRegion(
        .{ .x = src.x + border.left, .y = src.y, .w = src.w - border.left - border.right, .h = border.top },
        .{ .x = dst.x + border.left, .y = dst.y, .w = dst.w - border.left - border.right, .h = border.top },
    );
    try self.drawRegion(
        .{ .x = src.x + src.w - border.right, .y = src.y, .w = border.right, .h = border.top },
        .{ .x = dst.x + dst.w - border.right, .y = dst.y, .w = border.right, .h = border.top },
    );

    try self.drawRegion(
        .{ .x = src.x, .y = src.y + border.top, .w = border.left, .h = src.h - border.top - border.bottom },
        .{ .x = dst.x, .y = dst.y + border.top, .w = border.left, .h = dst.h - border.top - border.bottom },
    );
    try self.drawRegion(
        .{ .x = src.x + border.left, .y = src.y + border.top, .w = src.w - border.left - border.right, .h = src.h - border.top - border.bottom },
        .{ .x = dst.x + border.left, .y = dst.y + border.top, .w = dst.w - border.left - border.right, .h = dst.h - border.top - border.bottom },
    );
    try self.drawRegion(
        .{ .x = src.x + src.w - border.right, .y = src.y + border.top, .w = border.right, .h = src.h - border.top - border.bottom },
        .{ .x = dst.x + dst.w - border.right, .y = dst.y + border.top, .w = border.right, .h = dst.h - border.top - border.bottom },
    );

    try self.drawRegion(
        .{ .x = src.x, .y = src.y + src.h - border.bottom, .w = border.left, .h = border.bottom },
        .{ .x = dst.x, .y = dst.y + dst.h - border.bottom, .w = border.left, .h = border.bottom },
    );
    try self.drawRegion(
        .{ .x = src.x + border.left, .y = src.y + src.h - border.bottom, .w = src.w - border.left - border.right, .h = border.bottom },
        .{ .x = dst.x + border.left, .y = dst.y + dst.h - border.bottom, .w = dst.w - border.left - border.right, .h = border.bottom },
    );
    try self.drawRegion(
        .{ .x = src.x + src.w - border.right, .y = src.y + src.h - border.bottom, .w = border.right, .h = border.bottom },
        .{ .x = dst.x + dst.w - border.right, .y = dst.y + dst.h - border.bottom, .w = border.right, .h = border.bottom },
    );
}

/// Draws the given sprite with its top-left corner at the given position.
pub fn drawSprite(self: *Renderer, sprite: Spritesheet.Sprite, pos: math.Vec2(f32)) !void {
    const sprite_info = Spritesheet.Sprite.info.get(sprite);
    try self.drawRegion(sprite_info.rect, .{
        .x = pos.x,
        .y = pos.y,
        .w = sprite_info.rect.w,
        .h = sprite_info.rect.h,
    });
}

/// Draws the given sprite stretched to fill the given rectangle.
pub fn drawSpriteStretch(self: *Renderer, sprite: Spritesheet.Sprite, rect: math.Rect(f32)) !void {
    const sprite_info = Spritesheet.Sprite.info.get(sprite);
    try self.drawRegion(sprite_info.rect, rect);
}

/// Draws the given sprite as a nine-patch filling the given rectangle.
pub fn drawSprite9Patch(self: *Renderer, sprite: Spritesheet.Sprite, rect: math.Rect(f32)) !void {
    const sprite_info = Spritesheet.Sprite.info.get(sprite);
    try self.drawRegion9Patch(sprite_info.rect, sprite_info.border, rect);
}

pub fn print(self: *Renderer, text: []const u8, pos: math.Vec2(f32), color: math.Color(u8)) !void {
    var x = pos.x;
    var y = pos.y;

    try self.command_queue.switchColor(color);

    for (text) |char|
        switch (char) {
            ' ' => x += 5,
            '\n' => {
                x = 0;
                y += 6;
            },
            else => if (Spritesheet.Sprite.pebble(char)) |sprite| {
                try self.drawSprite(sprite, .{ .x = x, .y = y });
                x += Spritesheet.Sprite.info.get(sprite).rect.w + 1;
            },
        };

    try self.command_queue.switchColor(.white);
}

// /// Draws a line between the given points.
// pub fn drawLine(self: *Renderer, a: math.Vec2(f32), b: math.Vec2(f32), width: f32, color: math.Color(f32)) !void {
//     const corners = lineCorners(a, b, width);

//     const line_vertices: [4]Vertex = .{
//         .fromMath(self.mapPos(corners[0]), .{ .x = 0, .y = 0 }, color),
//         .fromMath(self.mapPos(corners[1]), .{ .x = 1, .y = 0 }, color),
//         .fromMath(self.mapPos(corners[2]), .{ .x = 0, .y = 1 }, color),
//         .fromMath(self.mapPos(corners[3]), .{ .x = 1, .y = 1 }, color),
//     };

//     const tri_vertices: [6]Vertex = .{
//         line_vertices[0],
//         line_vertices[2],
//         line_vertices[3],
//         line_vertices[0],
//         line_vertices[3],
//         line_vertices[1],
//     };

//     try self.vertex_queue.appendSliceBounded(&tri_vertices);
//     try self.command_queue.drawVertices(tri_vertices.len);
// }

// /// Draws the outline of a rectangle.
// pub fn drawRect(self: *Renderer, rect: math.Rect(f32), color: math.Color(f32)) !void {
//     const corners = rect.corners();

//     const rect_vertices: [4]Vertex = .{
//         .fromMath(self.mapPos(corners.tl), .{ .x = 0, .y = 0 }, color),
//         .fromMath(self.mapPos(corners.tr), .{ .x = 1, .y = 0 }, color),
//         .fromMath(self.mapPos(corners.bl), .{ .x = 0, .y = 1 }, color),
//         .fromMath(self.mapPos(corners.br), .{ .x = 1, .y = 1 }, color),
//     };

//     const tri_vertices: [6]Vertex = .{
//         rect_vertices[0],
//         rect_vertices[2],
//         rect_vertices[3],
//         rect_vertices[0],
//         rect_vertices[3],
//         rect_vertices[1],
//     };

//     try self.vertex_queue.appendSliceBounded(&tri_vertices);
//     try self.command_queue.drawVertices(tri_vertices.len);
// }

// /// Draws a filled rectangle.
// pub fn fillRect(self: *Renderer, rect: math.Rect(f32)) !void {
//     const corners = rect.corners();

//     const rect_vertices: [4]Vertex = .{
//         .fromMath(self.mapPos(corners.tl), .{ .x = 0, .y = 0 }),
//         .fromMath(self.mapPos(corners.tr), .{ .x = 1, .y = 0 }),
//         .fromMath(self.mapPos(corners.bl), .{ .x = 0, .y = 1 }),
//         .fromMath(self.mapPos(corners.br), .{ .x = 1, .y = 1 }),
//     };

//     const tri_vertices: [6]Vertex = .{
//         rect_vertices[0],
//         rect_vertices[2],
//         rect_vertices[3],
//         rect_vertices[0],
//         rect_vertices[3],
//         rect_vertices[1],
//     };

//     try self.vertex_queue.appendSliceBounded(&tri_vertices);
//     try self.command_queue.drawVertices(tri_vertices.len);
// }

// /// Draws a filled rectangle .
// pub fn fillUvRect(self: *Renderer, rect: math.Rect(f32), uv_rect: math.Rect(f32), color: math.Color(f32)) !void {
//     const corners = rect.corners();
//     const uv_corners = uv_rect.corners();

//     const rect_vertices: [4]Vertex = .{
//         .fromMath(self.mapPos(corners.tl), uv_corners.tl, color),
//         .fromMath(self.mapPos(corners.tr), uv_corners.tr, color),
//         .fromMath(self.mapPos(corners.bl), uv_corners.bl, color),
//         .fromMath(self.mapPos(corners.br), uv_corners.br, color),
//     };

//     const tri_vertices: [6]Vertex = .{
//         rect_vertices[0],
//         rect_vertices[2],
//         rect_vertices[3],
//         rect_vertices[0],
//         rect_vertices[3],
//         rect_vertices[1],
//     };

//     try self.vertex_queue.appendSliceBounded(&tri_vertices);
//     try self.command_queue.drawVertices(tri_vertices.len);
// }

// /// Draws a filled rectangle with rounded corners.
// ///
// /// The corner radius is clamped such that no two corners overlap.
// pub fn fillRoundedRect(self: *Renderer, rect: math.Rect(f32), corner_radius: f32, color: math.Color(f32)) !void {
//     const arc_detail = 4;

//     const corner_radius_clamped = @min(corner_radius, rect.w / 2, rect.h / 2);

//     const corners = rect.grow(-corner_radius_clamped).corners();

//     var arc_points: [arc_detail]math.Vec2(f32) = undefined;
//     for (&arc_points, 0..) |*point, i|
//         point.* = .rotate(.{ .y = -corner_radius_clamped }, -@as(f32, @floatFromInt(i)) / (arc_points.len - 2));

//     var points: [arc_detail * 4]Vertex = undefined;
//     for (0..arc_detail) |i| {
//         points[i * 2] =
//             .fromMath(self.mapPos(corners.tl.add(arc_points[i])), .zero, color);
//         points[i * 2 + 1] =
//             .fromMath(self.mapPos(corners.tr.add(arc_points[i].withNeg(.x))), .zero, color);
//         points[(arc_detail + i) * 2] =
//             .fromMath(self.mapPos(corners.bl.add(arc_points[arc_detail - i - 1].withNeg(.y))), .zero, color);
//         points[(arc_detail + i) * 2 + 1] =
//             .fromMath(self.mapPos(corners.br.add(arc_points[arc_detail - i - 1].neg())), .zero, color);
//     }

//     var vertices: [(points.len - 2) * 3]Vertex = undefined;
//     for (0..points.len - 2) |i| {
//         vertices[i * 3] = points[i];
//         vertices[i * 3 + 1] = points[i + 1];
//         vertices[i * 3 + 2] = points[i + 2];
//     }

//     try self.vertex_queue.append(&vertices);
//     try self.command_queue.push(.{ .draw_vertices = vertices.len });
// }

// pub fn fillCircle(self: *Renderer, center: math.Vec2(f32), radius: f32, color: math.Color(f32)) !void {
//     _ = self;
//     _ = center;
//     _ = radius;
//     _ = color;
//     // const arc_detail = 4;

//     // var arc_points: [arc_detail]math.Vec2(f32) = undefined;
//     // for (&arc_points, 0..) |*arc_point, i|
//     //     arc_point.* = .rotate(.{ .x = radius }, @as(f32, @floatFromInt(i)) / arc_points.len);

//     // var points: [4 * arc_detail]Vertex = undefined;
//     // for (&points, 0..) |*point, i| {
//     //     center.add(arc_points[i])
//     // }

//     // const points = [_]Vertex{};
// }

// /// Draws the given texture as a nine-patch rectangle.
// pub fn draw9Patch(
//     self: *Renderer,
//     sprite: Spritesheet.Sprite,
//     rect: math.Rect(f32),
//     margin_left: f32,
//     margin_right: f32,
//     margin_top: f32,
//     margin_bottom: f32,
// ) !void {
//     _ = self;
//     _ = sprite;
//     _ = rect;
//     _ = margin_left;
//     _ = margin_right;
//     _ = margin_top;
//     _ = margin_bottom;
//     @panic("TODO");
// }

// // pub fn print(self: *Renderer, text: []const u8, pos: math.Vec2(f32), color: math.Color(f32)) !void {
// //     for (text) |char| {
// //         const sprite: Spritesheet.Sprite = .pebble('a');
// //         const pixel_rect = sprite.pixel_rect();
// //         const uv_coords = sprite.uv_coords();

// //     }
// // }

// /// Clips subsequent draw operations to the given rectangle.
// pub fn clip(self: *Renderer, rect: ?math.Rect(f32)) !void {
//     _ = self;
//     _ = rect;
//     @compileError("TODO");
//     // return self._command_queue.push(.{
//     //     .switch_clip = if (rect) |r| blk: {
//     //         const pos = self.posToCoords(.{ .x = r.x, .y = r.y });
//     //         const size = (math.Vec2(f32){ .x = r.w, .y = r.h }).mul(self.scale).mul(2);
//     //         break :blk .{
//     //             .x = pos.x,
//     //             .y = pos.y,
//     //             .w = size.x,
//     //             .h = size.y,
//     //         };
//     //     } else null,
//     // });
// }

// Rendering

/// Renders all pending draw operations to the given window.
///
/// After calling this function, the renderer's queues will be empty and ready to draw anew.
///
/// Assumes the window was previously claimed by the renderer by calling `claimWindow`.
pub fn render(self: *Renderer, window: *sdl.SDL_Window) !void {
    const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(self._gpu_device) orelse
        return error.Sdl;
    defer _ = sdl.SDL_SubmitGPUCommandBuffer(command_buffer);

    var maybe_swapchain_texture: ?*sdl.SDL_GPUTexture = undefined;
    if (!sdl.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, window, &maybe_swapchain_texture, null, null))
        return error.Sdl;
    const swapchain_texture = maybe_swapchain_texture orelse return;

    {
        const copy_pass = sdl.SDL_BeginGPUCopyPass(command_buffer) orelse unreachable;
        defer sdl.SDL_EndGPUCopyPass(copy_pass);

        const transfer_ptr: [*]Vertex = @ptrCast(@alignCast(
            sdl.SDL_MapGPUTransferBuffer(self._gpu_device, self._gpu_transfer_buffer, false) orelse
                return error.Sdl,
        ));
        @memcpy(transfer_ptr, self.vertex_queue.items);
        sdl.SDL_UnmapGPUTransferBuffer(self._gpu_device, self._gpu_transfer_buffer);

        sdl.SDL_UploadToGPUBuffer(copy_pass, &.{
            .transfer_buffer = self._gpu_transfer_buffer,
        }, &.{
            .buffer = self._gpu_buffer,
            .size = @as(u32, @intCast(self.vertex_queue.items.len)) * @sizeOf(Vertex),
        }, false);

        self.vertex_queue.clearRetainingCapacity();
    }

    {
        const render_pass = sdl.SDL_BeginGPURenderPass(
            command_buffer,
            &.{
                .texture = swapchain_texture,
                .clear_color = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
                .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                .store_op = sdl.SDL_GPU_STOREOP_STORE,
            },
            1,
            null,
        ) orelse unreachable;
        defer sdl.SDL_EndGPURenderPass(render_pass);

        sdl.SDL_BindGPUGraphicsPipeline(render_pass, self._gpu_pipeline);
        sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &.{ .buffer = self._gpu_buffer }, 1);
        sdl.SDL_BindGPUFragmentSamplers(render_pass, 0, &.{ .texture = self.spritesheet._gpu_texture, .sampler = self._gpu_sampler }, 1);
        sdl.SDL_PushGPUFragmentUniformData(command_buffer, 0, &[4]f32{ 1.0, 1.0, 1.0, 1.0 }, @sizeOf([4]f32));

        var vertex_index: u32 = 0;
        for (self.command_queue._list.items) |command| {
            switch (command) {
                .draw_vertices => |vertex_count| {
                    sdl.SDL_DrawGPUPrimitives(render_pass, vertex_count, 1, vertex_index, 0);
                    vertex_index += vertex_count;
                },
                .switch_color => |color| sdl.SDL_PushGPUFragmentUniformData(command_buffer, 0, &.{
                    @as(f32, @floatFromInt(color.r)) / 255,
                    @as(f32, @floatFromInt(color.g)) / 255,
                    @as(f32, @floatFromInt(color.b)) / 255,
                    @as(f32, @floatFromInt(color.a)) / 255,
                }, @sizeOf(f32) * 4),
            }
        }
    }
}

/// Creates a swapchain structure for the given window.
///
/// The swapchain is owned by the caller and should be freed by calling `releaseWindow`.
pub fn claimWindow(self: *Renderer, window: *sdl.SDL_Window) !void {
    if (!sdl.SDL_ClaimWindowForGPUDevice(self._gpu_device, window))
        return error.Sdl;
    std.debug.assert(sdl.SDL_GetGPUSwapchainTextureFormat(self._gpu_device, window) == target_texture_format);
}

/// Destroys the swapchain structure for the given window.
///
/// Assumes the window was previously claimed by the renderer by calling `claimWindow`.
pub fn releaseWindow(self: *Renderer, window: *sdl.SDL_Window) void {
    sdl.SDL_ReleaseWindowFromGPUDevice(self._gpu_device, window);
}

/// Converts a screen position to normalized device coordinates.
pub fn mapPos(self: Renderer, pos: math.Vec2(f32)) math.Vec2(f32) {
    return math.Vec2(f32).from_simd(
        pos.to_simd() * self.scale.to_simd() * @as(math.Vec2(f32).Simd, @splat(2)) - @as(math.Vec2(f32).Simd, @splat(1)),
    ).withNeg(.y);
}

/// Returns the four vertices that make up a line of the given width between the given points.
fn lineCorners(a: math.Vec2(f32), b: math.Vec2(f32), width: f32) [4]math.Vec2(f32) {
    const unit = (b.sub(a).normalize() catch math.Vec2(f32).zero).mul(width / 2.0);
    const perp = math.Vec2(f32){ .x = unit.y, .y = -unit.x };
    return .{ a.sub(perp), a.add(perp), b.add(perp), b.sub(perp) };
}

/// Buffers rendering commands.
const CommandQueue = struct {
    /// The commands in the queue.
    _list: std.ArrayList(Command),
    /// The current color multiplier, as of the most recent command in the queue.
    _current_color: math.Color(u8) = .white,
    // /// The current clipping rectangle, as of the most recent command in the
    // /// queue.
    // _last_clip: ?math.Rect(f32) = null,

    /// Draws the given number of vertices from the vertex queue.
    pub fn drawVertices(self: *CommandQueue, count: u16) !void {
        if (self.last()) |last_cmd|
            if (last_cmd.* == .draw_vertices) {
                last_cmd.draw_vertices += count;
                return;
            };

        try self._list.appendBounded(.{ .draw_vertices = count });
    }

    /// Sets the color multiplier used for subsequent drawing operations.
    pub fn switchColor(self: *CommandQueue, color: math.Color(u8)) !void {
        if (std.meta.eql(self._current_color, color))
            return;
        self._current_color = color;

        if (self.last()) |last_cmd|
            if (last_cmd.* == .switch_color) {
                last_cmd.switch_color = color;
                return;
            };

        try self._list.appendBounded(.{ .switch_color = color });
    }

    /// Clears the command queue.
    pub fn clear(self: *CommandQueue) void {
        self._list.clearRetainingCapacity();
        self._current_color = .white;
    }

    /// Returns a pointer to the last command in the queue, if any.
    fn last(self: *CommandQueue) ?*Command {
        if (self._list.items.len == 0) return null;
        return &self._list.items[self._list.items.len - 1];
    }
};

/// A rendering command.
const Command = union(enum) {
    /// Draws a number of vertices from the vertex queue.
    draw_vertices: u32,
    /// Sets the current color multiplier.
    switch_color: math.Color(u8),
};

/// A unit of data passed to the vertex shader.
pub const Vertex = extern struct {
    // Position, in normalized device coordinates
    x: f32,
    y: f32,
    // Texture coordinates
    u: f32,
    v: f32,

    /// Constructs a vertex from `math` types.
    pub fn construct(pos: math.Vec2(f32), uv: math.Vec2(f32)) Vertex {
        return .{
            .x = pos.x,
            .y = pos.y,
            .u = uv.x,
            .v = uv.y,
        };
    }
};

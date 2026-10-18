//! Handles rendering and manages GPU resources.
//!
//! A render happens in the following steps:
//!
//! 1. The renderer's queues are cleared by calling `clear`.
//! 2. Draw operations are queued up with `draw*` and `switch*` calls.
//! 2. All queued drawing operations are rendered to a window by calling `render`.

// TODO: For portability, the renderer currently defers creating its rendering
// pipeline until the first time a window is claimed. The pipeline's parameters
// include the texture format used by rendering targets, but the texture format
// used by windows isn't known until one is passed in to be claimed. This puts
// significant work in an unexpected place. Also, if a window  with a different
// texture format is ever attempted to be claimed, the renderer will return an
// error, and if a claimed window's texture format ever changes, it's up to SDL
// to catch the error. Is there a better way?

// TODO: Support rendering to textures?

const builtin = @import("builtin");
const math = @import("../util/math.zig");
const sokol = @import("sokol");
const std = @import("std");

const Renderer = @This();

/// A queue of commands to be performed during rendering.
cmd_queue: CmdQueue,
/// A queue of vertices to be uploaded to the GPU.
vtx_queue: std.ArrayList(Vtx),
/// The spritesheet used by the renderer.
spritesheet: Spritesheet,

/// An allocator for commands and vertices.
gpa: std.mem.Allocator,
/// The GPU graphics pipeline used to render.
_pipeline: sokol.gfx.Pipeline = .{},
/// A GPU sampler used to sample vertex textures.
_sampler: sokol.gfx.Sampler,
/// A buffer of vertices in GPU memory.
///
/// The buffer's capacity is assumed to match that of `vtx_queue`.
_buffer: sokol.gfx.Buffer,

pub const Spritesheet = @import("Spritesheet.zig");

/// An error that might occur while drawing.
pub const DrawError = error{ OutOfMemory, Sdl };

/// The shader format used by the GPU.
const shader_format = switch (builtin.target.os.tag) {
    .linux => sdl.SDL_GPU_SHADERFORMAT_SPIRV,
    .macos => sdl.SDL_GPU_SHADERFORMAT_MSL,
    .windows => sdl.SDL_GPU_SHADERFORMAT_DXIL,
    else => @compileError("Unspecified shader format for target"),
};
/// The file extension used by shader files.
const shader_ext = switch (shader_format) {
    sdl.SDL_GPU_SHADERFORMAT_SPIRV => "spv",
    sdl.SDL_GPU_SHADERFORMAT_MSL => "msl",
    sdl.SDL_GPU_SHADERFORMAT_DXIL => "dxil",
    else => @compileError("Unknown shader file extension for shader format"),
};

/// A rendering command.
const Cmd = union(enum) {
    /// Draws a number of vertices from the vertex queue.
    draw_vertices: u32,
    /// Sets the current color multiplier.
    switch_color: math.Color(u8),
    /// Sets the current scale multiplier.
    switch_scale: math.Vec2(f32),
};

/// A buffer of rendering commands.
const CmdQueue = struct {
    /// The commands in the queue.
    _list: std.ArrayList(Cmd),
    /// The current color multiplier, as of the most recent command in the queue.
    _current_color: math.Color(u8) = .white,
    /// The current scale multiplier, as of the most recent command in the queue.
    _current_scale: math.Vec2(f32) = .one,

    /// Draws the given number of vertices from the vertex queue.
    ///
    /// Asserts that the queue can hold one additional item.
    pub fn drawVerticesAssumeCapacity(self: *CmdQueue, count: u32) !void {
        if (self.last()) |last_cmd|
            if (last_cmd.* == .draw_vertices) {
                last_cmd.draw_vertices += count;
                return;
            };

        self._list.appendAssumeCapacity(.{ .draw_vertices = count });
    }

    /// Draws the given number of vertices from the vertex queue.
    ///
    /// Allocates more memory as necessary.
    pub fn drawVerticesAlloc(self: *CmdQueue, gpa: std.mem.Allocator, count: u32) !void {
        try self._list.ensureUnusedCapacity(gpa, 1);
        try self.drawVerticesAssumeCapacity(count);
    }

    /// Sets the color multiplier used for subsequent drawing operations.
    ///
    /// Asserts that the queue can hold one additional item.
    pub fn switchColorAssumeCapacity(self: *CmdQueue, color: math.Color(u8)) !void {
        if (std.meta.eql(self._current_color, color))
            return;
        self._current_color = color;

        if (self.last()) |last_cmd|
            if (last_cmd.* == .switch_color) {
                last_cmd.switch_color = color;
                return;
            };

        self._list.appendAssumeCapacity(.{ .switch_color = color });
    }

    /// Sets the color multiplier used for subsequent drawing operations.
    ///
    /// Allocates more memory as necessary.
    pub fn switchColorAlloc(self: *CmdQueue, gpa: std.mem.Allocator, color: math.Color(u8)) !void {
        try self._list.ensureUnusedCapacity(gpa, 1);
        try self.switchColorAssumeCapacity(color);
    }

    /// Sets the scale multiplier used for subsequent drawing operations.
    ///
    /// Asserts that the queue can hold one additional item.
    pub fn switchScaleAssumeCapacity(self: *CmdQueue, scale: math.Vec2(f32)) !void {
        if (std.meta.eql(self._current_scale, scale))
            return;
        self._current_scale = scale;

        if (self.last()) |last_cmd|
            if (last_cmd.* == .switch_scale) {
                last_cmd.switch_scale = scale;
                return;
            };

        self._list.appendAssumeCapacity(.{ .switch_scale = scale });
    }

    /// Sets the scale multiplier used for subsequent drawing operations.
    ///
    /// Allocates more memory as necessary.
    pub fn switchScaleAlloc(self: *CmdQueue, gpa: std.mem.Allocator, scale: math.Vec2(f32)) !void {
        try self._list.ensureUnusedCapacity(gpa, 1);
        try self.switchScaleAssumeCapacity(scale);
    }

    /// Clears the command queue.
    pub fn clear(self: *CmdQueue) void {
        self._list.clearRetainingCapacity();
        self._current_color = .white;
        self._current_scale = .one;
    }

    /// Returns a pointer to the last command in the queue, if any.
    fn last(self: *CmdQueue) ?*Cmd {
        if (self._list.items.len == 0) return null;
        return &self._list.items[self._list.items.len - 1];
    }
};

/// A vertex passed to the GPU.
pub const Vtx = extern struct {
    /// The *x*-position of the vertex, in screen coordinates.
    x: f32,
    /// The *y*-position of the vertex, in screen coordinates.
    y: f32,
    /// The *x*-position at which to sample the spritesheet, in UV coordinates.
    u: f32,
    /// The *y*-position at which to sample the spritesheet, in UV coordinates.
    v: f32,

    /// Constructs a vertex from `math` types.
    pub fn construct(pos: math.Vec2(f32), uv: math.Vec2(f32)) Vtx {
        return .{
            .x = pos.x,
            .y = pos.y,
            .u = uv.x,
            .v = uv.y,
        };
    }
};

/// Returns a new renderer.
///
/// The renderer is owned by the caller and must be freed by calling `deinit`.
pub fn init(gpa: std.mem.Allocator) !Renderer {
    var cmd_queue: CmdQueue = .{ ._list = try .initCapacity(gpa, 512) };
    errdefer cmd_queue._list.deinit(gpa);

    var vtx_queue: std.ArrayList(Vtx) = try .initCapacity(gpa, 1024);
    errdefer vtx_queue.deinit(gpa);

    var io_single_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_single_threaded.io();

    var spritesheet = try Spritesheet.init(io, gpa);
    errdefer spritesheet.deinit();

    const sampler = sokol.gfx.makeSampler(.{});
    errdefer sokol.gfx.destroySampler(sampler);

    const buffer = sokol.gfx.makeBuffer(.{
        .usage = .{ .vertex_buffer = true, .write_transient = true },
        .size = @intCast(vtx_queue.capacity * @sizeOf(Vtx)),
    });
    errdefer sokol.gfx.destroyBuffer(buffer);

    const vert_shader_code = try std.Io.Dir.cwd().readFileAlloc(io, "res/shaders/vert." ++ shader_ext, gpa, .unlimited);
    defer gpa.free(vert_shader_code);

    const frag_shader_code = try std.Io.Dir.cwd().readFileAlloc(io, "res/shaders/frag." ++ shader_ext, gpa, .unlimited);
    defer gpa.free(frag_shader_code);

    const shader = sokol.gfx.makeShader(.{
        .vertex_func = .{
            .source = vert_shader_code,
            .entry = "VertMain",
        },
    });
    defer sokol.gfx.destroyShader(shader);

    const pipeline = sokol.gfx.makePipeline(.{
        .shader = shader,
    });
    errdefer sokol.gfx.destroyPipeline(pipeline);

    return .{
        .vtx_queue = vtx_queue,
        .cmd_queue = cmd_queue,
        .spritesheet = spritesheet,
        .gpa = gpa,
        ._pipeline = pipeline,
        ._sampler = sampler,
        ._buffer = buffer,
    };
}

/// Initializes the renderer's GPU pipeline with its current target texture
/// format.
fn initPipeline(self: *Renderer) !void {
    var io_single_threaded: std.Io.Threaded = .init_single_threaded;
    const io = io_single_threaded.io();

    const file_buf = try self.gpa.alloc(u8, 1024);
    defer self.gpa.free(file_buf);

    const vert_shader_code = try std.Io.Dir.cwd().readFile(io, "res/shaders/vert." ++ shader_ext, file_buf);
    const vert_shader = sdl.SDL_CreateGPUShader(self._gpu_device, &.{
        .code_size = vert_shader_code.len,
        .code = vert_shader_code.ptr,
        .entrypoint = "VertMain",
        .format = shader_format,
        .stage = sdl.SDL_GPU_SHADERSTAGE_VERTEX,
        .num_uniform_buffers = 1,
    }) orelse
        return error.Sdl;
    defer sdl.SDL_ReleaseGPUShader(self._gpu_device, vert_shader);

    const frag_shader_code = try std.Io.Dir.cwd().readFile(io, "res/shaders/frag." ++ shader_ext, file_buf);
    const frag_shader = sdl.SDL_CreateGPUShader(self._gpu_device, &.{
        .code_size = frag_shader_code.len,
        .code = frag_shader_code.ptr,
        .entrypoint = "FragMain",
        .format = shader_format,
        .stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
        .num_samplers = 1,
        .num_uniform_buffers = 1,
    }) orelse
        return error.Sdl;
    defer sdl.SDL_ReleaseGPUShader(self._gpu_device, frag_shader);

    self._gpu_pipeline = sdl.SDL_CreateGPUGraphicsPipeline(self._gpu_device, &.{
        .vertex_shader = vert_shader,
        .fragment_shader = frag_shader,
        .vertex_input_state = .{
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = &.{
                .slot = 0,
                .pitch = @sizeOf(Vtx),
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
                .format = self._gpu_target_texture_format,
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
}

/// Frees the renderer.
///
/// The renderer should not be used after calling this function.
pub fn deinit(self: *Renderer) void {
    self.cmd_queue._list.deinit(self.gpa);
    self.vtx_queue.deinit(self.gpa);
    self.spritesheet.deinit(self._gpu_device);
    sokol.gfx.destroyBuffer(self._buffer);
    sokol.gfx.destroySampler(self._sampler);
    sokol.gfx.destroyPipeline(self._pipeline);
    self.* = undefined;
}

// Drawing

/// Cancels all pending draw operations.
pub fn clear(self: *Renderer) void {
    self.vtx_queue.clearRetainingCapacity();
    self.cmd_queue.clear();
}

/// Sets the scale multiplier applied to subsequent draw operations.
pub fn switchScale(self: *Renderer, x: f32, y: f32) !void {
    try self.cmd_queue.switchScaleAlloc(self.gpa, .{ .x = x, .y = y });
}

/// Sets the color multiplier applied to subsequent draw operations.
pub fn switchColor(self: *Renderer, color: math.Color(u8)) !void {
    try self.cmd_queue.switchColorAlloc(self.gpa, color);
}

/// Draws the given vertices.
pub fn drawVertices(self: *Renderer, vertices: []const Vtx) !void {
    if (vertices.len >= self.vtx_queue.capacity - self.vtx_queue.items.len) {
        try self.vtx_queue.ensureUnusedCapacity(self.gpa, vertices.len);

        const gpu_buffer = sdl.SDL_CreateGPUBuffer(self._gpu_device, &.{
            .usage = sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
            .size = @intCast(self.vtx_queue.capacity * @sizeOf(Vtx)),
        }) orelse
            return error.Sdl;
        errdefer sdl.SDL_ReleaseGPUBuffer(self._gpu_device, gpu_buffer);

        const gpu_transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(self._gpu_device, &.{
            .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = @intCast(self.vtx_queue.capacity * @sizeOf(Vtx)),
        }) orelse
            return error.Sdl;
        errdefer sdl.SDL_ReleaseGPUTransferBuffer(self._gpu_device, gpu_transfer_buffer);

        self._gpu_buffer = gpu_buffer;
        self._gpu_transfer_buffer = gpu_transfer_buffer;
    }
    self.vtx_queue.appendSliceAssumeCapacity(vertices);

    try self.cmd_queue.drawVerticesAlloc(self.gpa, @intCast(vertices.len));
}

/// Draws the given region of the spritesheet to the given rectangle.
pub fn drawRegion(
    self: *Renderer,
    src: math.Rect(u8),
    dst: math.Rect(f32),
) !void {
    const corners = dst.corners();

    const rect_vertices: [4]Vtx = .{
        .construct(corners.tl, .{ .x = @as(f32, src.x) / Spritesheet.width, .y = @as(f32, src.y) / Spritesheet.height }),
        .construct(corners.tr, .{ .x = @as(f32, src.x + src.w) / Spritesheet.width, .y = @as(f32, src.y) / Spritesheet.height }),
        .construct(corners.bl, .{ .x = @as(f32, src.x) / Spritesheet.width, .y = @as(f32, src.y + src.h) / Spritesheet.height }),
        .construct(corners.br, .{ .x = @as(f32, src.x + src.w) / Spritesheet.width, .y = @as(f32, src.y + src.h) / Spritesheet.height }),
    };

    try self.drawVertices(&.{
        rect_vertices[0],
        rect_vertices[2],
        rect_vertices[3],
        rect_vertices[0],
        rect_vertices[3],
        rect_vertices[1],
    });
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

/// Draws the given region of the spritesheet repeated to fill the given rectangle.
pub fn drawRegionRepeat(
    self: *Renderer,
    src: math.Rect(u8),
    dst: math.Rect(f32),
) !void {
    const x_fit = dst.w / src.w;
    const y_fit = dst.h / src.h;
    const x_repeat_count: u16 = @trunc(x_fit);
    const y_repeat_count: u16 = @trunc(y_fit);
    const x_repeat_fr = x_fit - x_repeat_count;
    const y_repeat_fr = y_fit - y_repeat_count;

    for (0..x_repeat_count) |x|
        for (0..y_repeat_count) |y|
            try self.drawRegion(src, .{
                .x = dst.x + src.w * @as(f32, @floatFromInt(x)),
                .y = dst.y + src.h * @as(f32, @floatFromInt(y)),
                .w = src.w,
                .h = src.h,
            });

    for (0..x_repeat_count) |x|
        try self.drawRegion(src, .{
            .x = dst.x + src.w * @as(f32, @floatFromInt(x)),
            .y = dst.y + src.h * y_repeat_count,
            .w = src.w,
            .h = src.h * y_repeat_fr,
        });

    for (0..y_repeat_count) |y|
        try self.drawRegion(src, .{
            .x = dst.x + src.w * x_repeat_count,
            .y = dst.y + src.h * @as(f32, @floatFromInt(y)),
            .w = src.w * x_repeat_fr,
            .h = src.h,
        });

    try self.drawRegion(src, .{
        .x = dst.x + src.w * x_repeat_count,
        .y = dst.y + src.h * y_repeat_count,
        .w = src.w * x_repeat_fr,
        .h = src.h * y_repeat_fr,
    });
}

/// Draws the given sprite with its top-left corner at the given position.
pub fn drawSprite(self: *Renderer, sprite: Spritesheet.Sprite, pos: math.Vec2(f32)) !void {
    const sprite_info = sprite.info();
    try self.drawRegion(sprite_info.rect, .{
        .x = pos.x,
        .y = pos.y,
        .w = sprite_info.rect.w,
        .h = sprite_info.rect.h,
    });
}

/// Draws the given sprite stretched to fill the given rectangle.
pub fn drawSpriteStretch(self: *Renderer, sprite: Spritesheet.Sprite, rect: math.Rect(f32)) !void {
    try self.drawRegion(sprite.info().rect, rect);
}

/// Draws the given sprite repeated to fill the given rectangle.
pub fn drawSpriteRepeat(self: *Renderer, sprite: Spritesheet.Sprite, rect: math.Rect(f32)) !void {
    try self.drawRegionRepeat(sprite.info().rect, rect);
}

/// Draws the given sprite as a nine-patch filling the given rectangle.
pub fn drawSprite9Patch(self: *Renderer, sprite: Spritesheet.Sprite, rect: math.Rect(f32)) !void {
    const sprite_info = sprite.info();
    try self.drawRegion9Patch(sprite_info.rect, sprite_info.border, rect);
}

pub fn print(self: *Renderer, text: []const u8, pos: math.Vec2(f32)) !void {
    var x = pos.x;
    var y = pos.y;

    for (text) |char|
        switch (char) {
            ' ' => x += 5,
            '\n' => {
                x = 0;
                y += 6;
            },
            else => if (Spritesheet.Sprite.pebble(char)) |sprite| {
                try self.drawSprite(sprite, .{ .x = x, .y = y });
                x += sprite.info().rect.w + 1;
            },
        };
}

// Rendering

/// Renders all pending draw operations to the given window.
///
/// After calling this function, the renderer's queues will be empty and ready to draw anew.
///
/// Assumes the window was previously claimed by the renderer by calling `claimWindow`.
pub fn render(self: *Renderer) !void {
    sokol.gfx.writeBufferTransient(.{
        .src = .{ .data = .{ .ptr = self.vtx_queue.items.ptr } },
        .dst = .{ .buffer = self._buffer },
        .size = @as(u32, @intCast(self.vtx_queue.items.len)) * @sizeOf(Vtx),
    });

    sokol.gfx.beginPass(.{
        .swapchain = sokol.glue.swapchain(),
    });

    {
        const copy_pass = sdl.SDL_BeginGPUCopyPass(command_buffer) orelse unreachable;
        defer sdl.SDL_EndGPUCopyPass(copy_pass);

        const transfer_ptr: [*]Vtx = @ptrCast(@alignCast(
            sdl.SDL_MapGPUTransferBuffer(self._gpu_device, self._gpu_transfer_buffer, false) orelse
                return error.Sdl,
        ));
        @memcpy(transfer_ptr, self.vtx_queue.items);
        sdl.SDL_UnmapGPUTransferBuffer(self._gpu_device, self._gpu_transfer_buffer);

        sdl.SDL_UploadToGPUBuffer(copy_pass, &.{
            .transfer_buffer = self._gpu_transfer_buffer,
        }, &.{
            .buffer = self._gpu_buffer,
            .size = @as(u32, @intCast(self.vtx_queue.items.len)) * @sizeOf(Vtx),
        }, false);

        self.vtx_queue.clearRetainingCapacity();
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
        sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, &[2]f32{ 1.0, 1.0 }, @sizeOf([2]f32));
        sdl.SDL_BindGPUFragmentSamplers(render_pass, 0, &.{ .texture = self.spritesheet._gpu_texture, .sampler = self._gpu_sampler }, 1);
        sdl.SDL_PushGPUFragmentUniformData(command_buffer, 0, &[4]f32{ 1.0, 1.0, 1.0, 1.0 }, @sizeOf([4]f32));

        var vtx_index: u32 = 0;
        for (self.cmd_queue._list.items) |cmd| {
            switch (cmd) {
                .draw_vertices => |vtx_count| {
                    sokol.gfx.draw(vtx_index, vtx_count, 1);
                    vtx_index += vtx_count;
                },
                .switch_color => |color| sdl.SDL_PushGPUFragmentUniformData(command_buffer, 0, &[4]f32{
                    @as(f32, color.r) / 255,
                    @as(f32, color.g) / 255,
                    @as(f32, color.b) / 255,
                    @as(f32, color.a) / 255,
                }, @sizeOf([4]f32)),
                .switch_scale => |scale| sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, &[2]f32{
                    scale.x,
                    scale.y,
                }, @sizeOf([2]f32)),
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
    if (self._gpu_target_texture_format == sdl.SDL_GPU_TEXTUREFORMAT_INVALID) {
        self._gpu_target_texture_format = sdl.SDL_GetGPUSwapchainTextureFormat(self._gpu_device, window);
        try self.initPipeline();
    } else if (self._gpu_target_texture_format != sdl.SDL_GetGPUSwapchainTextureFormat(self._gpu_device, window))
        return error.InvalidTargetTextureFormat;
}

/// Destroys the swapchain structure for the given window.
///
/// Assumes the window was previously claimed by the renderer by calling `claimWindow`.
pub fn releaseWindow(self: *Renderer, window: *sdl.SDL_Window) void {
    sdl.SDL_ReleaseWindowFromGPUDevice(self._gpu_device, window);
}

/// Returns the four vertices that make up a line of the given width between the given points.
fn lineCorners(a: math.Vec2(f32), b: math.Vec2(f32), width: f32) [4]math.Vec2(f32) {
    const unit = (b.sub(a).normalize() catch math.Vec2(f32).zero).mul(width / 2.0);
    const perp = math.Vec2(f32){ .x = unit.y, .y = -unit.x };
    return .{ a.sub(perp), a.add(perp), b.add(perp), b.sub(perp) };
}

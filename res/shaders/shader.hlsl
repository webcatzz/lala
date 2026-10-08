Texture2D tex : register(t0);
SamplerState tex_sampler : register(s0);

cbuffer VertUniform : register(b0, space1) {
    float2 scale_mult;
}

cbuffer FragUniform : register(b0, space1) {
    float4 color_mult;
}

struct Vertex {
    float2 pos : POSITION;
    float2 uv : TEXCOORD;
};

struct Fragment {
    float4 pos : SV_POSITION;
    float2 uv : TEXCOORD;
};

Fragment VertMain(Vertex vert) {
    float2 pos = vert.pos * scale_mult * 2 - 1;
    Fragment frag;
    frag.pos = float4(pos.x, -pos.y, 0.0, 1.0);
    frag.uv = vert.uv;
    return frag;
}

float4 FragMain(Fragment frag) : SV_TARGET {
    return tex.Sample(tex_sampler, frag.uv) * color_mult;
}
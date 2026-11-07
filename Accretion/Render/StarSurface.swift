import SpriteKit

/// "Living plasma" for star bodies: boiling granulation cells, limb darkening and a slow spin,
/// drawn inside the existing glow sprite. One shared shader, so SpriteKit can still batch the draws;
/// each star gets its own pattern through the `a_seed` attribute.
@MainActor
enum StarSurface {
    /// Bodies smaller than this stay plain glows: the detail would be invisible and cost fill-rate.
    static let minRadius = 7.0

    static let shader: SKShader = {
        let shader = SKShader(source: source)
        shader.attributes = [SKAttribute(name: "a_seed", type: .float)]
        shader.uniforms = [SKUniform(name: "u_speed", float: 1)]
        return shader
    }()

    /// 0 freezes the surface (Reduce Motion).
    static func setAnimated(_ animated: Bool) {
        shader.uniformNamed("u_speed")?.floatValue = animated ? 1 : 0
    }

    static func apply(to node: SKSpriteNode, seed: Int) {
        node.shader = shader
        // Spread seeds so neighbouring ids look unrelated.
        let value = Float((seed &* 7919) % 1000) / 1000 * 97
        node.setValue(SKAttributeValue(float: value), forAttribute: "a_seed")
    }

    // Glow texture: solid core up to 1/1.7 of the radius, then a soft halo (see GameScene.makeGlowTexture).
    private static let source = """
    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }

    float noise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        vec2 u = f * f * (3.0 - 2.0 * f);
        float a = hash(i);
        float b = hash(i + vec2(1.0, 0.0));
        float c = hash(i + vec2(0.0, 1.0));
        float d = hash(i + vec2(1.0, 1.0));
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    float fbm(vec2 p) {
        float v = 0.0;
        float amp = 0.5;
        for (int i = 0; i < 3; i++) {
            v += amp * noise(p);
            p = p * 2.03 + vec2(1.7, 9.2);
            amp *= 0.5;
        }
        return v;
    }

    void main() {
        vec4 glow = texture2D(u_texture, v_tex_coord);
        vec2 uv = v_tex_coord * 2.0 - 1.0;
        float r = length(uv);
        float core = 1.0 / 1.7;
        float t = u_time * u_speed;

        // Slow spin, each star its own direction and pace.
        float spin = (fract(a_seed * 0.37) - 0.5) * 0.25 * t;
        float cs = cos(spin);
        float sn = sin(spin);
        vec2 p = vec2(cs * uv.x - sn * uv.y, sn * uv.x + cs * uv.y) / core;

        // Fake sphere: squeeze the pattern toward the rim so it reads as a ball, not a disc.
        float rr = clamp(r / core, 0.0, 1.0);
        float mu = sqrt(max(1.0 - rr * rr, 0.0));
        vec2 sphere = p * (1.0 + 0.6 * (1.0 - mu));

        // Two layers of cells drifting against each other = boiling plasma.
        float cells = fbm(sphere * 3.2 + vec2(a_seed, t * 0.18));
        float fine = fbm(sphere * 7.5 - vec2(t * 0.25, a_seed * 0.5));
        float plasma = cells * 0.7 + fine * 0.3;

        vec3 tint = v_color_mix.rgb;
        // Stars glow: the darkest cells are still the full tint, bright cells burn toward white.
        vec3 hot = mix(tint, vec3(1.0), 0.75);
        vec3 cool = tint * 0.85;
        vec3 surface = mix(cool, hot, smoothstep(0.35, 0.75, plasma));
        // Limb darkening, like the real Sun: white-hot middle, deeper colour at the edge.
        surface *= 0.78 + 0.32 * mu;
        surface = mix(surface, vec3(1.0), 0.25 * mu * mu);

        // Inside the disc use the surface; outside keep the original soft halo.
        float inside = 1.0 - smoothstep(core * 0.93, core, r);
        vec3 halo = tint * glow.a;
        vec3 rgb = mix(halo, surface, inside);
        float alpha = glow.a * v_color_mix.a;
        gl_FragColor = vec4(rgb * alpha, alpha);
    }
    """
}

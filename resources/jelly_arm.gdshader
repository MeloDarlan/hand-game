shader_type spatial;

// Deformação tipo jelly apenas no antebraço.
// O VERTEX no Godot 4 já chega com a skinning aplicada; BONE_INDICES/WEIGHTS
// são usados para isolar os vértices ligados ao bone do antebraço.

uniform vec3 jelly_offsets[6];
uniform float bend_amount = 1.0;
uniform float stretch = 0.0;
uniform float squash_amount = 1.0;
uniform float wrist_y = 0.35;
uniform float arm_length = 5.1;

uniform vec4 albedo_color : source_color = vec4(0.8, 0.061, 0.036, 1.0);
uniform float roughness_value = 0.45;

const int SEGMENTS = 6;


float arm_parameter(vec3 position) {
	return clamp((wrist_y - position.y) / max(arm_length, 0.001), 0.0, 1.0);
}


vec3 chain_offset(float t) {
	float scaled = clamp(t, 0.0, 0.9999) * float(SEGMENTS - 1);
	int index0 = int(floor(scaled));
	int index1 = min(index0 + 1, SEGMENTS - 1);
	float blend = fract(scaled);
	return mix(jelly_offsets[index0], jelly_offsets[index1], blend);
}


void vertex() {
	float t = arm_parameter(VERTEX);
	float taper = smoothstep(0.0, 0.09, t) * (1.0 - smoothstep(0.92, 1.0, t));
	float mask = taper;

	// Squash/stretch ao longo do antebraço, ancorado no punho.
	VERTEX.y = wrist_y + (VERTEX.y - wrist_y) * (1.0 + stretch * squash_amount * mask);

	// Curvatura/wobble.
	vec3 offset = chain_offset(t);
	VERTEX += offset * bend_amount * mask;

	// Correção aproximada da normal para a luz não achatar durante a curvatura.
	float dt = 0.04;
	float t0 = clamp(t - dt, 0.0, 1.0);
	float t1 = clamp(t + dt, 0.0, 1.0);
	vec3 slope = (chain_offset(t1) - chain_offset(t0)) / max((t1 - t0) * arm_length, 0.001);
	NORMAL = normalize(NORMAL - vec3(slope.x, 0.0, slope.z) * 0.35 * mask);
}


void fragment() {
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
}

// =====================================================================
//  PS1-ядро для spatial-шейдеров. Подключается из ps1*.gdshader.
//  Варианты (через #define до #include):
//   PS1_CUTOUT   — вырезание по альфе, двусторонний (листья, бумаги, решётки);
//   PS1_UNSHADED — без динамического света: свет запечён в вершинный цвет,
//                  как в большинстве игр PS1 (уровни, персонажи с тинтом).
//  Эффекты:
//   * Vertex wobble — вершины привязываются к пиксельной сетке экрана;
//   * аффинное наложение текстур (без перспективной коррекции);
//   * nearest-фильтрация без мипмапов;
//   * мерцание ламп по альфе вершинного цвета (только PS1_UNSHADED);
//   * опциональное понижение глубины цвета текстуры.
// =====================================================================

#if defined(PS1_CUTOUT) && defined(PS1_UNSHADED)
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;
#elif defined(PS1_CUTOUT)
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;
#elif defined(PS1_UNSHADED)
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;
#else
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;
#endif

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);

// 0 = выкл, 1 = полная привязка к сетке.
uniform float snap_strength : hint_range(0.0, 1.0) = 1.0;
// Размер сетки относительно внутреннего разрешения: 1.0 = по пикселям, 0.5 = вдвое грубее.
uniform float snap_resolution_scale : hint_range(0.1, 2.0) = 1.0;
// 1 = чистые аффинные текстуры как на PS1, 0 = обычная перспективная коррекция.
uniform float affine_strength : hint_range(0.0, 1.0) = 1.0;
// Уровней на канал для текстуры (0 = не трогать). 16 ≈ 4-битная палитра.
uniform float texture_color_levels : hint_range(0.0, 64.0) = 0.0;
uniform bool use_vertex_color = true;
#ifdef PS1_UNSHADED
// Яркость запечённого света: вершинный цвет 0.625 = текстура как есть (PS1-шные «пересветы» до 1.6x).
uniform float light_gain = 1.6;
#endif
#ifdef PS1_CUTOUT
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
#endif

varying vec3 ps1_affine_uv;
varying vec4 ps1_vcol;

void vertex() {
	vec2 uv = UV * uv_scale + uv_offset;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);

	// Vertex wobble: снап NDC-координат к сетке внутреннего разрешения.
	if (snap_strength > 0.0 && clip.w > 0.0001) {
		vec2 grid = max(VIEWPORT_SIZE * 0.5 * snap_resolution_scale, vec2(1.0));
		vec2 ndc = clip.xy / clip.w;
		vec2 snapped = floor(ndc * grid + 0.5) / grid;
		clip.xy = mix(ndc, snapped, snap_strength) * clip.w;
	}
	POSITION = clip;

	// Аффинный трюк: UV*w интерполируется перспективно, деление на w во фрагменте
	// «отменяет» коррекцию — получаем линейную в экранном пространстве интерполяцию.
	ps1_affine_uv = vec3(uv * clip.w, clip.w);
	UV = uv;
	ps1_vcol = use_vertex_color ? COLOR : vec4(1.0);
#ifdef PS1_UNSHADED
	// Альфа вершинного цвета > 0 — «зерно» мерцающей лампы этой комнаты.
	if (use_vertex_color && COLOR.a < 0.999) {
		float seed = COLOR.a * 255.0;
		float t = mod(floor(TIME * 14.0), 997.0);
		float r = fract(sin(seed * 91.7 + t * 12.9898) * 43758.5453);
		float r2 = fract(sin(seed * 17.3 + mod(floor(TIME * 0.7), 991.0) * 3.17) * 9631.7);
		float fl = (r2 < 0.4 && r < 0.4) ? 0.28 : 1.0;
		ps1_vcol = vec4(COLOR.rgb * fl, 1.0);
	} else {
		ps1_vcol.a = 1.0;
	}
#endif
}

void fragment() {
	vec2 affine = ps1_affine_uv.xy / ps1_affine_uv.z;
	vec2 uv = mix(UV, affine, affine_strength);
	vec4 tex = texture(albedo_texture, uv);
	if (texture_color_levels > 0.0) {
		tex.rgb = floor(tex.rgb * texture_color_levels + 0.5) / texture_color_levels;
	}
	vec4 col = tex * albedo_color * ps1_vcol;
#ifdef PS1_UNSHADED
	col.rgb *= light_gain;
#endif
	ALBEDO = col.rgb;
#ifndef PS1_UNSHADED
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
#endif
#ifdef PS1_CUTOUT
	ALPHA = col.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
#endif
}

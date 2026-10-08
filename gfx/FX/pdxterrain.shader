# Sharp Terrain on Low Shader Quality - modified copy of
# game/gfx/FX/pdxterrain.shader from Victoria 3 1.13.11.
#
# With Shader Quality set to Low the game draws the map with Effect PdxTerrainLowSpec,
# which samples the terrain detail textures per *vertex* (CalculateDetailsLowSpec in
# lowspec_terrain.fxh, called from TerrainVertexLowSpec) and passes the result down as
# an interpolant, so the ground is smeared across every terrain triangle no matter how
# high the texture quality is. The low spec pixel shader also does no lighting at all:
# the terrain normal is computed per vertex and then never used, so hills and mountains
# are only visible through their textures.
#
# This file only changes the two low spec terrain effects:
#   * the detail textures, the colormap and the flatmap are sampled per *pixel*
#     (CalculateDetails, the same function the Medium/High pixel shader uses)
#   * cheap relief shading: one dot product of the terrain normal (plus the detail
#     normal maps CalculateDetails samples anyway) with the sun direction, scaled so
#     that flat ground keeps exactly the vanilla low spec brightness
# Everything that makes the higher shader settings expensive stays off: no shadow map,
# no cubemap lighting, no specular, no harvest condition, pollution or devastation
# materials, no SSAO weighting.
#
# Changes vs vanilla:
#   * new options block and function SharpReliefShading in the PixelShader Code block
#   * new MainCode PixelShaderLowSpecSharp
#   * Effect PdxTerrainLowSpec      -> VertexShader + PixelShaderLowSpecSharp
#   * Effect PdxTerrainLowSpecSkirt -> VertexShaderSkirt + PixelShaderLowSpecSharp
# The vanilla PixelShaderLowSpec block is left in place, unreferenced, for diffing
# against future game patches.

Includes = {
	"cw/terrain.fxh"
	"cw/heightmap.fxh"
	"cw/utility.fxh"
	"cw/lighting.fxh"
	"cw/shadow.fxh"
	"cw/camera.fxh"
	"jomini/jomini_lighting.fxh"
	"jomini/jomini_province_overlays.fxh"
	"jomini/jomini_water.fxh"
	"lowspec_terrain.fxh"
	"sharedconstants.fxh"
	"standardfuncsgfx.fxh"
	"distance_fog.fxh"
	"coloroverlay.fxh"
	"coloroverlay_harvest_condition.fxh"
	"coloroverlay_naval_mission.fxh"
	"dynamic_masks.fxh"
	"fog_of_war.fxh"
	"ssao_struct.fxh"
	"harvest_condition.fxh"
}


VertexStruct VS_OUTPUT_PDX_TERRAIN
{
	float4 Position			: PDX_POSITION;
	float3 WorldSpacePos	: TEXCOORD0;
	float4 ShadowProj		: TEXCOORD1;
};

VertexStruct VS_OUTPUT_PDX_TERRAIN_SHADOW
{
	float4 Position			: PDX_POSITION;
};

VertexShader =
{
	Code
	[[
		VS_OUTPUT_PDX_TERRAIN TerrainVertex( float2 WithinNodePos, float2 NodeOffset, float NodeScale, float2 LodDirection, float LodLerpFactor )
		{
			STerrainVertex Vertex = CalcTerrainVertex( WithinNodePos, NodeOffset, NodeScale, LodDirection, LodLerpFactor );

			#ifdef TERRAIN_FLAT_MAP_LERP
				Vertex.WorldSpacePos.y = lerp( Vertex.WorldSpacePos.y, _FlatmapHeight, _FlatmapLerp );
			#endif
			#ifdef TERRAIN_FLAT_MAP
				Vertex.WorldSpacePos.y = _FlatmapHeight;
			#endif

			VS_OUTPUT_PDX_TERRAIN Out;
			Out.WorldSpacePos = Vertex.WorldSpacePos;

			Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Vertex.WorldSpacePos, 1.0 ) );
			Out.ShadowProj = mul( ShadowMapTextureMatrix, float4( Vertex.WorldSpacePos, 1.0 ) );

			return Out;
		}
	]]

	MainCode VertexShader
	{
		Input = "VS_INPUT_PDX_TERRAIN"
		Output = "VS_OUTPUT_PDX_TERRAIN"
		Code
		[[
			PDX_MAIN
			{
				return TerrainVertex( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w );
			}
		]]
	}

	MainCode VertexShaderSkirt
	{
		Input = "VS_INPUT_PDX_TERRAIN_SKIRT"
		Output = "VS_OUTPUT_PDX_TERRAIN"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PDX_TERRAIN Out = TerrainVertex( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w );

				float3 Position = FixPositionForSkirt( Out.WorldSpacePos, Input.VertexID );
				Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Position, 1.0 ) );

				return Out;
			}
		]]
	}

		MainCode VertexShaderShadow
	{
		Input = "VS_INPUT_PDX_TERRAIN"
		Output = "VS_OUTPUT_PDX_TERRAIN_SHADOW"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PDX_TERRAIN_SHADOW Out;
				Out.Position = TerrainVertex( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w ).Position;
				return Out;
			}
		]]
	}

	MainCode VertexShaderShadowSkirt
	{
		Input = "VS_INPUT_PDX_TERRAIN_SKIRT"
		Output = "VS_OUTPUT_PDX_TERRAIN_SHADOW"
		Code
		[[
			PDX_MAIN
			{
				VS_OUTPUT_PDX_TERRAIN TerrainVert = TerrainVertex( Input.UV, Input.NodeOffset_Scale_Lerp.xy, Input.NodeOffset_Scale_Lerp.z, Input.LodDirection, Input.NodeOffset_Scale_Lerp.w );
				float3 Position = FixPositionForSkirt( TerrainVert.WorldSpacePos, Input.VertexID );

				VS_OUTPUT_PDX_TERRAIN_SHADOW Out;
				Out.Position = FixProjectionAndMul( ViewProjectionMatrix, float4( Position, 1.0 ) );

				return Out;
			}
		]]
	}
}



PixelShader =
{
	# PdxTerrain uses texture index 0 - 6

	# Jomini specific
	TextureSampler ShadowMap
	{
		Ref = PdxShadowmap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		CompareFunction = less_equal
		SamplerType = "Compare"
	}

	# Game specific
	TextureSampler EnvironmentMap
	{
		Ref = JominiEnvironmentMap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
		Type = "Cube"
	}
	TextureSampler FlatmapTexture
	{
		Ref = Flatmap
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Clamp"
	}

	TextureSampler Equator
	{
		Index = 10
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Clamp"
		File = "gfx/map/textures/equator_line.dds"
		srgb = yes
	}

	Code
	[[
		void CropToWorldSize( in VS_OUTPUT_PDX_TERRAIN Input )
		{
			float LerpFactor = saturate( ( Input.Position.z - 0.9 ) * 10.0 );
			clip( vec2(1.0) - ( Input.WorldSpacePos.xz - float2( lerp( 0.1, 2.0, LerpFactor ), 0.0 ) ) * _WorldSpaceToTerrain0To1 );
		}

		// Sharp Terrain options. Comment a #define out, re-run install.sh and restart the
		// game to drop that part.
		//
		// SHARPOPT_RELIEF_SHADING: hills and mountains shaded by the sun direction.
		//   Without it the terrain stays as flat as vanilla low spec, only sharp.
		// SHARPOPT_DETAIL_NORMALS: the detail normal maps (rock, sand ripples, fields)
		//   take part in that shading. Free - CalculateDetails samples them anyway.
		// SHARPOPT_FLATMAP_OVERLAY: the paper map's folds, grid lines and equator while
		//   zooming out to it, as on Medium/High; vanilla low spec skips them and they
		//   pop in when the flat map takes over. Three texture reads, only while the
		//   map is blending to paper.
		#define SHARPOPT_RELIEF_SHADING
		#define SHARPOPT_DETAIL_NORMALS
		#define SHARPOPT_FLATMAP_OVERLAY

		// Relief shading strength: 0 = flat, 1 = full Lambert relative to flat ground.
		// The factor is clamped so that steep slopes away from the sun never go black
		// and slopes facing it never blow out.
		#define SHARP_RELIEF_STRENGTH 0.65
		#define SHARP_RELIEF_MIN 0.45
		#define SHARP_RELIEF_MAX 1.25

		// Brightness factor for a normal, 1.0 on flat ground. Vanilla low spec is unlit,
		// so the factor is relative to a horizontal surface instead of absolute lighting:
		// that keeps plains and the colour overlays at their vanilla brightness.
		float SharpReliefShading( float3 Normal )
		{
			float FlatNdotL = max( ToSunDir.y, 0.25 );
			float Lit = saturate( dot( Normal, ToSunDir ) ) / FlatNdotL;
			return clamp( lerp( 1.0, Lit, SHARP_RELIEF_STRENGTH ), SHARP_RELIEF_MIN, SHARP_RELIEF_MAX );
		}

		float3 ApplyFlatmapEquator( float3 Flatmap, float2 MapCoords, float Opacity )
		{
			float2 TextureSize;
			PdxTex2DSize( Equator, TextureSize );

			float2 EquatorUV = MapCoords;
			float AspectRatioMap = MapSize.y / MapSize.x;
			float AspectRatioTexture = TextureSize.x / TextureSize.y;
			float SizeY = MapSize.y / TextureSize.y;
			EquatorUV.y = 1.0 - EquatorUV.y - _FlatmapEquatorPosition;
			EquatorUV.y *= AspectRatioMap * AspectRatioTexture;

			if ( _FlatmapEquatorTiling > 0.0 )
			{
				EquatorUV *= _FlatmapEquatorTiling;
			}
			float4 EquatorTexture = PdxTex2D( Equator, EquatorUV );

			if ( EquatorUV.y > 0.0 && EquatorUV.y < 1.0)
			{
				// Edge fade
				float FadeAlpha = 1.0f;
				float FadeDistance = 0.05f;
				float FadeRight = RemapClamped( EquatorUV.y, 0.0, FadeDistance, 0.0, 1.0 );
				float FadeLeft = RemapClamped( EquatorUV.y, 1.0 - FadeDistance, 1.0, 1.0, 0.0 );
				FadeAlpha = FadeRight * FadeLeft;

				Flatmap = lerp( Flatmap, EquatorTexture.rgb, EquatorTexture.a * Opacity * FadeAlpha );
			}

			return Flatmap;
		}

		float3 ApplyFlatmapOverlay( float3 Flatmap, float2 MapCoords )
		{
			float4 OverlayTexture = PdxTex2D( FlatmapOverlayTexture, float2( MapCoords.x, 1.0 - MapCoords.y ) );

			float LandMask = PdxTex2DLod0( LandMaskMap, float2( MapCoords.x, 1.0 - MapCoords.y ) ).r;
			float LandAlpha = ( 1.0 - ( LandMask * ( 1.0 - _FlatmapOverlayLandOpacity ) ) );
			Flatmap = lerp( Flatmap, _FlatmapFoldsColor.rgb, OverlayTexture.r * _FlatmapFoldsColor.a * LandAlpha );
			Flatmap = lerp( Flatmap, _FlatmapLinesColor.rgb, OverlayTexture.g * _FlatmapLinesColor.a * LandAlpha );
			Flatmap = ApplyFlatmapEquator( Flatmap, MapCoords, LandAlpha * OverlayTexture.b );

			Flatmap = SoftLight( Flatmap, _FlatmapDetailsColor.rgb, saturate( OverlayTexture.a ) * _FlatmapDetailsColor.a );
			return Flatmap;
		}
	]]

	MainCode PixelShader
	{
		Input = "VS_OUTPUT_PDX_TERRAIN"
		Output = "PS_COLOR_SSAO"
		Code
		[[
			float3 GameCalculateEnvironmentLighting( SMaterialProperties MaterialProps, SLightingProperties LightingProps )
			{
				float3 DiffuseIBL = vec3( 0.0f );
				float3 SpecularIBL = vec3( 0.0f );

				// Cubemap Diffuse light
				float3 RotatedDiffuseCubemapUV = mul( CastTo3x3( LightingProps._CubemapYRotation ), MaterialProps._Normal );
				float3 DiffuseRad = PdxTexCubeLod( EnvironmentMap, RotatedDiffuseCubemapUV, ( PDX_NumMips - 1 - PDX_MipOffset ) ).rgb * LightingProps._CubemapIntensity; // TODO, maybe we should split diffuse and spec intensity?
				DiffuseIBL = DiffuseRad * MaterialProps._DiffuseColor;

				// Cubemap specular light
				float3 ReflectionVector = reflect( -LightingProps._ToCameraDir, MaterialProps._Normal );
				float3 DominantReflectionVector = GetSpecularDominantDir( MaterialProps._Normal, ReflectionVector, MaterialProps._Roughness );

				float NdotR = saturate( dot( MaterialProps._Normal, DominantReflectionVector ) );
				float3 SpecularReflection = F_Schlick( MaterialProps._SpecularColor, vec3(1.0), NdotR );
				float SpecularFade = GetReductionInMicrofacets( MaterialProps._Roughness );

				float MipLevel = BurleyToMipSimple( MaterialProps._PerceptualRoughness );
				float3 RotatedSpecularCubemapUV = mul( CastTo3x3( LightingProps._CubemapYRotation ), DominantReflectionVector );
				float3 SpecularRad = PdxTexCubeLod( EnvironmentMap, RotatedSpecularCubemapUV, MipLevel ).rgb * LightingProps._CubemapIntensity; // TODO, maybe we should split diffuse and spec intensity?
				SpecularIBL = SpecularRad * SpecularFade * SpecularReflection;

				return DiffuseIBL + SpecularIBL;
			}

			float3 GameCalculateSunLighting( SMaterialProperties MaterialProps, SLightingProperties LightingProps, float3 WorldSpacePos, inout float IridescenceMask  )
			{
				float3 DiffuseLight = vec3( 0.0f );
				float3 SpecularLight = vec3( 0.0f );

				// Light vectors
				float3 H = normalize( LightingProps._ToCameraDir + LightingProps._ToLightDir );
				float NdotV = abs( dot( MaterialProps._Normal, LightingProps._ToCameraDir ) ) + 1e-5;
				float NdotL = saturate( dot( MaterialProps._Normal, LightingProps._ToLightDir ) );
				float NdotH = saturate( dot( MaterialProps._Normal, H ) );
				float LdotH = saturate( dot( LightingProps._ToLightDir, H ) );
				float3 LightIntensity = LightingProps._LightIntensity * NdotL * LightingProps._ShadowTerm;

				// Sun diffuse light
				float DiffuseBRDF = CalcDiffuseBRDF( NdotV, NdotL, LdotH, MaterialProps._PerceptualRoughness );
				DiffuseLight = DiffuseBRDF * MaterialProps._DiffuseColor * LightIntensity;

				// Iridescense for sun specular
				GetIridescense( MaterialProps, NdotV, EnvironmentMap, WorldSpacePos, IridescenceMask );

				// Sun specular light
				float3 F = F_Schlick( MaterialProps._SpecularColor, vec3( 1.0f ), LdotH );
				float D = D_GGX( NdotH, lerp( 0.03f , 1.0f , MaterialProps._Roughness ) );		// Remap to avoid super small and super bright highlights
				#ifdef PDX_SimpleLighting
					float Vis = V_Optimized( LdotH, MaterialProps._Roughness );
				#else
					float Vis = V_Schlick( NdotL, NdotV, MaterialProps._Roughness );
				#endif
				Vis = lerp( Vis, 1.0f, IridescenceMask );				// Iridescence calculates its own fresnel
				SpecularLight = D * F * Vis * LightIntensity;

				// Iridescense rimlight specular
				#ifdef HIGH_QUALITY_SHADERS
					CalculateIridescenceRimlight( MaterialProps, LightingProps, SpecularLight, IridescenceMask );
				#endif

				return DiffuseLight + SpecularLight;
			}

			PDX_MAIN
			{
				PS_COLOR_SSAO Out;

				CropToWorldSize( Input );
				#ifndef UNDERWATER
					clip( GetHeight( Input.WorldSpacePos.xz ) - _WaterHeight + 1.0 ); // +0.1 to avoid gap between water and mesh
				#endif

				// Materials
				float4 DetailDiffuse = vec4( 1.0 );
				float3 DetailNormal = vec3( 1.0 );
				float4 DetailMaterial = vec4( 1.0 );

				// UV Coordinates
				float2 MapCoords = Input.WorldSpacePos.xz * _WorldSpaceToTerrain0To1;
				float2 ProvinceCoords = Input.WorldSpacePos.xz / _ProvinceMapSize;

				// Get terrain material
				CalculateDetails( Input.WorldSpacePos.xz, DetailDiffuse, DetailNormal, DetailMaterial );

				// Harvest conditions
				float WaterNormalLerp = 0.0;
				ApplyHarvestConditionTerrain( DetailDiffuse, DetailNormal, DetailMaterial, Input.WorldSpacePos, WaterNormalLerp );

				float IridescenceMask = 0.0f;
				#ifndef UNDERWATER
					// Dynamic mask alpha
					ApplyPollutionMaterial( DetailDiffuse, DetailNormal, DetailMaterial, Input.WorldSpacePos.xz, IridescenceMask );
					ApplyDevastationMaterial( DetailDiffuse, DetailNormal, DetailMaterial, Input.WorldSpacePos.xz );
				#endif

				// Normals
				float3 Normal = CalculateNormal( Input.WorldSpacePos.xz );
				float3 ReorientedNormal = ReorientNormal( lerp( Normal, float3( 0.0, 1.0, 0.0 ), WaterNormalLerp ), DetailNormal );

				// Colormap overlay
				float3 ColorMap = PdxTex2D( ColorTexture, float2( MapCoords.x, 1.0 - MapCoords.y ) ).rgb;
				float3 Diffuse = SoftLight( DetailDiffuse.rgb, ColorMap, ( 1 - DetailMaterial.r ) );

				// Border color overlay
				float3 ColorOverlay;
				float PreLightingBlend;
				float PostLightingBlend;

				#ifndef UNDERWATER
					GameProvinceOverlayAndBlend( ProvinceCoords, Input.WorldSpacePos, ColorOverlay, PreLightingBlend, PostLightingBlend );
					Diffuse = ApplyColorOverlay( Diffuse, ColorOverlay, saturate( PreLightingBlend ) );
				#endif

				// Light and shadow
				float ShadowTerm = CalculateShadow( Input.ShadowProj, ShadowMap );

				DetailMaterial.a = ScaleRoughnessByDistance( DetailMaterial.a, Input.WorldSpacePos );
				SMaterialProperties MaterialProps = GetMaterialProperties( Diffuse, ReorientedNormal, DetailMaterial.a, DetailMaterial.g, DetailMaterial.b );
				SLightingProperties LightingProps = GetSunLightingProperties( Input.WorldSpacePos, ShadowTerm );

				float3 FinalColor = GameCalculateEnvironmentLighting( MaterialProps, LightingProps );
				FinalColor += GameCalculateSunLighting( MaterialProps, LightingProps, Input.WorldSpacePos, IridescenceMask );

				// Effects, post light
				ApplyHarvestConditionTerrainPostLight( FinalColor, DetailDiffuse.a, Input.WorldSpacePos );

				#ifndef UNDERWATER
					FinalColor = ApplyColorOverlay( FinalColor, ColorOverlay, PostLightingBlend );
					FinalColor = ApplyFogOfWar( FinalColor, Input.WorldSpacePos );
					FinalColor = GameApplyDistanceFog( FinalColor, Input.WorldSpacePos );

					// Blend from Terrain to Flatmap
					#ifdef TERRAIN_FLAT_MAP_LERP
						// Flatmap texture and style
						float3 Flatmap = PdxTex2D( FlatmapTexture, float2( MapCoords.x, 1.0 - MapCoords.y ) ).rgb;
						Flatmap = ApplyDynamicFlatmap( Flatmap, ProvinceCoords, Input.WorldSpacePos.xz );

						// Border color overlay on flatmap
						Flatmap *= lerp( vec3( 1.0 ), ColorOverlay, saturate( PreLightingBlend + PostLightingBlend ) );

						Flatmap = ApplyFlatmapOverlay( Flatmap, MapCoords );

						FinalColor = lerp( FinalColor, Flatmap, _FlatmapLerp);
					#endif

					if ( _EnableMapNavalMission == true )
					{
						ApplyNavalMissionOverlay( FinalColor, ProvinceCoords, MapCoords, _FlatmapLerp );
					}

					// Highlight color overlay
					FinalColor = ApplyHighlight( FinalColor, ProvinceCoords );
				#endif //not UNDERWATER

				// Underwater
				float Alpha = 1.0;
				#ifdef UNDERWATER
					Alpha = CompressWorldSpace( Input.WorldSpacePos );
				#endif

				// Debug
				#ifdef TERRAIN_DEBUG
					TerrainDebug( FinalColor, Input.WorldSpacePos );
				#endif
				DebugReturn( FinalColor, MaterialProps, LightingProps, EnvironmentMap );

				// Output
				Out.Color = float4( FinalColor, Alpha );
				float3 SSAOAlphaFixed = vec3( 1.0f ) - _SSAOAlphaTerrain; // Reduces the applied SSAO on terrain
				#ifndef UNDERWATER
					SSAOAlphaFixed = SSAOAlphaFixed + PostLightingBlend;
				#endif
				Out.SSAOColor = float4( saturate( SSAOAlphaFixed ), saturate( Alpha - GameCalculateDistanceFogFactor ( Input.WorldSpacePos ) ) );

				return Out;
			}
		]]
	}

	MainCode PixelShaderLowSpec
	{
		Input = "VS_OUTPUT_PDX_TERRAIN_LOW_SPEC"
		Output = "PS_COLOR_SSAO"
		Code
		[[
			PDX_MAIN
			{
				PS_COLOR_SSAO Out;

				float LerpFactor = saturate( ( Input.Position.z - 0.9 ) * 10.0 );
				clip( vec2(1.0) - ( Input.WorldSpacePos.xz - float2( lerp( 0.1, 2.0, LerpFactor ), 0.0 ) ) * _WorldSpaceToTerrain0To1 );

				float3 DetailDiffuse = saturate( Input.DetailDiffuse );
				float4 DetailMaterial = saturate( Input.DetailMaterial );
				float3 ColorMap = saturate( Input.ColorMap );
				float3 Flatmap = saturate( Input.Flatmap );
				float3 Normal = saturate( Input.Normal );

				// UV Coordinates
				float2 MapCoords = Input.WorldSpacePos.xz * _WorldSpaceToTerrain0To1;
				float2 ProvinceCoords = Input.WorldSpacePos.xz / _ProvinceMapSize;

				// Colormap overlay
				float3 Diffuse = SoftLight( DetailDiffuse.rgb, ColorMap, ( 1 - DetailMaterial.r ) );

				// Border color overlay
				float3 ColorOverlay;
				float PreLightingBlend;
				float PostLightingBlend;
				GameProvinceOverlayAndBlend( ProvinceCoords, Input.WorldSpacePos, ColorOverlay, PreLightingBlend, PostLightingBlend );
				Diffuse = ApplyColorOverlay( Diffuse, ColorOverlay, saturate( PreLightingBlend ) );

				#ifndef UNDERWATER
					// Effects, post light
					Diffuse = ApplyColorOverlay( Diffuse, ColorOverlay, PostLightingBlend );
					Diffuse = ApplyFogOfWar( Diffuse, Input.WorldSpacePos );
					Diffuse = GameApplyDistanceFog( Diffuse, Input.WorldSpacePos );

					// Blend from Terrain to Flatmap
					#ifdef TERRAIN_FLAT_MAP_LERP
						// Flatmap texture and style
						Flatmap = ApplyDynamicFlatmap( Flatmap, ProvinceCoords, Input.WorldSpacePos.xz );

						// Border color overlay on flatmap
						Flatmap *= lerp( vec3( 1.0 ), ColorOverlay, saturate( PreLightingBlend + PostLightingBlend ) );
						Diffuse = lerp( Diffuse, Flatmap, _FlatmapLerp );
					#endif

					if ( _EnableMapNavalMission == true )
					{
						ApplyNavalMissionOverlay( Diffuse, ProvinceCoords, MapCoords, _FlatmapLerp );
					}

					// Highlight color overlay
					Diffuse = ApplyHighlight( Diffuse, ProvinceCoords );

				#endif//not UNDERWATER

				// Output
				Out.Color = float4( Diffuse, 1.0f );
				Out.SSAOColor = float4( vec4( 1.0f ) );

				return Out;
			}
		]]
	}

	# Low spec terrain with the detail textures sampled per pixel. Takes the plain
	# VS_OUTPUT_PDX_TERRAIN (same vertex shader as Medium/High), so none of the per
	# vertex detail work of VertexShaderLowSpec runs. Apart from the per pixel reads
	# and the relief shading it follows PixelShaderLowSpec line by line.
	MainCode PixelShaderLowSpecSharp
	{
		Input = "VS_OUTPUT_PDX_TERRAIN"
		Output = "PS_COLOR_SSAO"
		Code
		[[
			PDX_MAIN
			{
				PS_COLOR_SSAO Out;

				CropToWorldSize( Input );

				// UV Coordinates
				float2 MapCoords = Input.WorldSpacePos.xz * _WorldSpaceToTerrain0To1;
				float2 ProvinceCoords = Input.WorldSpacePos.xz / _ProvinceMapSize;

				// The actual fix: per pixel detail sampling with proper mip selection,
				// instead of the per vertex CalculateDetailsLowSpec.
				float4 DetailDiffuse = vec4( 1.0 );
				float3 DetailNormal = float3( 0.0, 1.0, 0.0 );
				float4 DetailMaterial = vec4( 1.0 );
				CalculateDetails( Input.WorldSpacePos.xz, DetailDiffuse, DetailNormal, DetailMaterial );

				// Colormap overlay
				float3 ColorMap = PdxTex2D( ColorTexture, float2( MapCoords.x, 1.0 - MapCoords.y ) ).rgb;
				float3 Diffuse = SoftLight( DetailDiffuse.rgb, ColorMap, ( 1 - DetailMaterial.r ) );

				// Border color overlay
				float3 ColorOverlay;
				float PreLightingBlend;
				float PostLightingBlend;
				GameProvinceOverlayAndBlend( ProvinceCoords, Input.WorldSpacePos, ColorOverlay, PreLightingBlend, PostLightingBlend );
				Diffuse = ApplyColorOverlay( Diffuse, ColorOverlay, saturate( PreLightingBlend ) );

				// Where Medium/High light the terrain: relief only, relative to flat ground
				#ifdef SHARPOPT_RELIEF_SHADING
					float3 Normal = CalculateNormal( Input.WorldSpacePos.xz );
					#ifdef SHARPOPT_DETAIL_NORMALS
						Normal = ReorientNormal( Normal, DetailNormal );
					#endif
					Diffuse *= SharpReliefShading( Normal );
				#endif

				#ifndef UNDERWATER
					// Effects, post light
					Diffuse = ApplyColorOverlay( Diffuse, ColorOverlay, PostLightingBlend );
					Diffuse = ApplyFogOfWar( Diffuse, Input.WorldSpacePos );
					Diffuse = GameApplyDistanceFog( Diffuse, Input.WorldSpacePos );

					// Blend from Terrain to Flatmap
					#ifdef TERRAIN_FLAT_MAP_LERP
						// Flatmap texture and style
						float3 Flatmap = PdxTex2D( FlatmapTexture, float2( MapCoords.x, 1.0 - MapCoords.y ) ).rgb;
						Flatmap = ApplyDynamicFlatmap( Flatmap, ProvinceCoords, Input.WorldSpacePos.xz );

						// Border color overlay on flatmap
						Flatmap *= lerp( vec3( 1.0 ), ColorOverlay, saturate( PreLightingBlend + PostLightingBlend ) );

						#ifdef SHARPOPT_FLATMAP_OVERLAY
							Flatmap = ApplyFlatmapOverlay( Flatmap, MapCoords );
						#endif

						Diffuse = lerp( Diffuse, Flatmap, _FlatmapLerp );
					#endif

					if ( _EnableMapNavalMission == true )
					{
						ApplyNavalMissionOverlay( Diffuse, ProvinceCoords, MapCoords, _FlatmapLerp );
					}

					// Highlight color overlay
					Diffuse = ApplyHighlight( Diffuse, ProvinceCoords );

				#endif//not UNDERWATER

				// Output
				Out.Color = float4( Diffuse, 1.0f );
				Out.SSAOColor = float4( vec4( 1.0f ) );

				return Out;
			}
		]]
	}

	MainCode PixelShaderFlatmap
	{
		Input = "VS_OUTPUT_PDX_TERRAIN"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{
				CropToWorldSize( Input );

				float2 MapCoords = Input.WorldSpacePos.xz * _WorldSpaceToTerrain0To1;
				float2 ProvinceCoords = Input.WorldSpacePos.xz / _ProvinceMapSize;

				// Flatmap texture and style
				float3 Flatmap = PdxTex2D( FlatmapTexture, float2( MapCoords.x, 1.0 - MapCoords.y ) ).rgb;
				Flatmap = ApplyDynamicFlatmap( Flatmap, ProvinceCoords, Input.WorldSpacePos.xz );

				// Border color overlay
				float3 ColorOverlay;
				float PreLightingBlend;
				float PostLightingBlend;
				GameProvinceOverlayAndBlend( ProvinceCoords, Input.WorldSpacePos, ColorOverlay, PreLightingBlend, PostLightingBlend );

				// Apply harvest condition overlay on flatmap only
				if ( _EnableMapHarvestCondition == true )
				{
					ApplyHarvestConditionOverlay( ColorOverlay, ProvinceCoords );
				}

				Flatmap *= lerp( vec3( 1.0 ), ColorOverlay, saturate( PreLightingBlend + PostLightingBlend ) );

				float CountryId = SampleControllerIndex( MapCoords ).r;
				if( CountryId < 0  && !_EnableMapPowerBloc )	 // Remove fluff overlay from war areas and powerblocs
				{
					Flatmap = ApplyFlatmapOverlay( Flatmap, MapCoords );
				}

				// Flatmap color
				float3 FinalColor = Flatmap;

				if ( _EnableMapNavalMission == true )
				{
					ApplyNavalMissionOverlay( FinalColor, ProvinceCoords, MapCoords, _FlatmapLerp );
				}

				// Highlight color overlay
				FinalColor = ApplyHighlight( FinalColor, ProvinceCoords );

				// Debug
				#ifdef TERRAIN_DEBUG
					TerrainDebug( FinalColor, Input.WorldSpacePos );
				#endif

				return float4( FinalColor, 1 );
			}
		]]
	}

	MainCode PixelShaderShadow
	{
		Input = "VS_OUTPUT_PDX_TERRAIN_SHADOW"
		Output = "void"
		Code
		[[
			PDX_MAIN
			{
			}
		]]
	}
}

RasterizerState RasterizerState
{
	DepthBias = 150
	SlopeScaleDepthBias = 0
}
RasterizerState ShadowRasterizerState
{
	DepthBias = 0
	SlopeScaleDepthBias = 2
}

Effect PdxTerrain
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"

	Defines = { "TERRAIN_WRAP_X" }
}

Effect PdxTerrainLowSpec
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderLowSpecSharp"

	Defines = { "TERRAIN_WRAP_X" }
}

Effect PdxTerrainSkirt
{
	VertexShader = "VertexShaderSkirt"
	PixelShader = "PixelShader"

	Defines = { "TERRAIN_WRAP_X" }
}

Effect PdxTerrainLowSpecSkirt
{
	VertexShader = "VertexShaderSkirt"
	PixelShader = "PixelShaderLowSpecSharp"

	Defines = { "TERRAIN_WRAP_X" }
}

Effect PdxTerrainFlat
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShaderFlatmap"

	Defines = { "TERRAIN_FLAT_MAP" }
}

Effect PdxTerrainFlatSkirt
{
	VertexShader = "VertexShaderSkirt"
	PixelShader = "PixelShaderFlatmap"

	Defines = { "TERRAIN_FLAT_MAP" }
}

Effect PdxTerrainShadow
{
	VertexShader = "VertexShaderShadow"
	PixelShader = "PixelShaderShadow"
	RasterizerState = ShadowRasterizerState
}

Effect PdxTerrainShadowSkirt
{
	VertexShader = "VertexShaderShadowSkirt"
	PixelShader = "PixelShaderShadow"
	RasterizerState = ShadowRasterizerState
}

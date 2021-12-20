#ifndef WATERSIMULATION_FORWARDBASE
#define WATERSIMULATION_FORWARDBASE

#include "../ShaderLibrary/CustomLightingLib.hlsl"

struct Attributes
{
    float4 vertex : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float4 positionWS : TEXCOORD0;
    float2 uv : TEXCOORD1;
    float3 normalWS : TEXCOORD2;
    float3 tangentWS : TEXCOORD3;
    float3 binormalWS : TEXCOORD4;
    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
      float4 shadowCoord : TEXCOORD5; // 计算阴影坐标
   #endif
    
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

float Wave(float3 positionOS, float amplitude, float speed, float waveLength, float2 direction)
{
    float t = _Time.y;
    float w = 2 / waveLength;
    float phase = speed * w;
    float H = amplitude * sin(direction * (positionOS.xz * direction) * w + t * phase);
    return H;
}

float DerivativesHeightX(float3 positionOS, float amplitude, float speed, float waveLength, float2 direction)
{
    float t = _Time.y;
    float w = 2 / waveLength;
    float phase = speed * w;
    return w * direction.x * amplitude * cos(direction * positionOS.xz * w + t * phase);
}

float DerivativesHeightY(float3 positionOS, float amplitude, float speed, float waveLength, float2 direction)
{
    float t = _Time.y;
    float w = 2 / waveLength;
    float phase = speed * w;
    return w * direction.y * amplitude * cos(direction * positionOS.xz * w + t * phase);
}



inline void InitializeInputDotData(InputWaterData inputData, Light mainLight, out InputDotData inputDotData)
{
    inputDotData.NdotL = dot(inputData.normalWS, mainLight.direction.xyz);
    inputDotData.NdotLClamp = saturate(dot(inputData.normalWS, mainLight.direction.xyz));
    inputDotData.HalfLambert = inputDotData.NdotL * 0.5 + 0.5;
    half3 halfDir = SafeNormalize(mainLight.direction + inputData.viewDirectionWS);
    inputDotData.LdotH = saturate(dot(mainLight.direction.xyz, halfDir.xyz));
    inputDotData.NdotH = saturate(dot(inputData.normalWS.xyz, halfDir.xyz));
    inputDotData.NdotV = saturate(dot(inputData.normalWS.xyz, inputData.viewDirectionWS.xyz));
    
    #if defined(_RECEIVE_SHADOWS_OFF)
        inputDotData.atten = 1;
    #else
        
        inputDotData.atten = mainLight.shadowAttenuation * mainLight.distanceAttenuation;
    #endif

    #if _PCSS_SHADOW
        inputDotData.atten = SAMPLE_TEXTURE2D(_PCSSShadowmapTexture, sampler_PCSSShadowmapTexture, inputData.screenUV.xy).x;
        half4 shadowParams = GetMainLightShadowParams();
        inputDotData.atten = lerp(1, inputDotData.atten, shadowParams.x);
        half fade = GetShadowFade(inputData.positionWS.xyz);
        inputDotData.atten = lerp(inputDotData.atten, 1, fade);
    #else
        inputDotData.atten = mainLight.shadowAttenuation * mainLight.distanceAttenuation;
    #endif
}

void InitializeInputData(Varyings input, half3 normalTS, out InputWaterData inputData)
{
	inputData = (InputWaterData)0;
	inputData.positionWS = input.positionWS;

	#if defined(_NORMALMAP)
		//half sgn = input.tangentWS.w;      // should be either +1 or -1
		inputData.normalWS = TransformTangentToWorld(normalTS, half3x3(input.tangentWS.xyz, input.bitangentWS.xyz, input.normalWS.xyz));
	#else
		inputData.normalWS = input.normalWS;
	#endif

	inputData.normalWS = normalize(inputData.normalWS);

	#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
		inputData.shadowCoord = input.shadowCoord;
	#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
		inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
	#else
		inputData.shadowCoord = half4(0, 0, 0, 0);
	#endif

	half3 viewDirWS = GetCameraPositionWS() - inputData.positionWS;
	viewDirWS = SafeNormalize(viewDirWS);
	inputData.viewDirectionWS = viewDirWS;
	inputData.bakedGI = SampleSH(inputData.normalWS);
}

half DirectBRDFSpecular2(BRDFBaseData brdfData, half3 LoH, half3 NoH)
{
	half d = NoH * NoH * brdfData.roughness2MinusOne + 1.00001f;

	half LoH2 = LoH * LoH;
	half specularTerm = brdfData.roughness2 / ((d * d) * max(0.1h, LoH2) * brdfData.normalizationTerm);

	// On platforms where half actually means something, the denominator has a risk of overflow
	// clamp below was added specifically to "fix" that, but dx compiler (we convert bytecode to metal/gles)
	// sees that specularTerm have only non-negative terms, so it skips max(0,..) in clamp (leaving only min(100,...))
	#if defined (SHADER_API_MOBILE) || defined (SHADER_API_SWITCH)
	specularTerm = specularTerm - HALF_MIN;
	specularTerm = clamp(specularTerm, 0.0, 100.0); // Prevent FP16 overflow on mobiles
	#endif

	return specularTerm;
}

// 高光函数
// 如果是_STYLIZED， specularMap 当作高光大小
// 如果是_PHONG， 光滑度来自光滑度通道
// 如果是_GGX, 光滑度来自光滑度通道，并且乘上specularColor！
half3 CalculateSpecular(WaterSimulationSurfaceData surfData, InputDotData inputDotData, BRDFBaseData brdfData)
{
	half ndoth = inputDotData.NdotH;
	half3 spec = DirectBRDFSpecular2(brdfData, inputDotData.LdotH, inputDotData.NdotH) * brdfData.specColor;

	spec = max(0.001f, spec);
	return spec;
}

inline half3 GetMainSpecularColor(WaterSimulationSurfaceData surfData, InputDotData inputDotData, BRDFBaseData brdfData)
{
	half3 specular = CalculateSpecular(surfData, inputDotData, brdfData) * surfData.albedo;
	return specular;
}

Varyings Vertex (Attributes input)
{
    Varyings output = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    float3 vertex = input.vertex.xyz;
    float h1 = Wave(vertex, _Amplitude1, _Speed1, _WaveLength1, _Direction1.xy);
    float h2 = Wave(vertex, _Amplitude2, _Speed2, _WaveLength2, _Direction2.xy);
    float h3 = Wave(vertex, _Amplitude3, _Speed3, _WaveLength3, _Direction3.xy);
    vertex.y += (h1 + h2 + h3);

    float b1 = DerivativesHeightX(vertex, _Amplitude1, _Speed1, _WaveLength1, _Direction1.xy);
    float b2 = DerivativesHeightX(vertex, _Amplitude2, _Speed2, _WaveLength2, _Direction2.xy);
    float b3 = DerivativesHeightX(vertex, _Amplitude3, _Speed3, _WaveLength3, _Direction3.xy);
    float b = b1 + b2 + b3;
    float3 binormalOS = float3(1, 0, b);

    float t1 = DerivativesHeightY(vertex, _Amplitude1, _Speed1, _WaveLength1, _Direction1.xy);
    float t2 = DerivativesHeightY(vertex, _Amplitude2, _Speed2, _WaveLength2, _Direction2.xy);
    float t3 = DerivativesHeightY(vertex, _Amplitude3, _Speed3, _WaveLength3, _Direction3.xy);
    float t = t1 + t2 + t3;
    float3 tangentOS = float3(0, 1, t);

    float3 normalOS = float3(-b, -t, 1);
    
    VertexPositionInputs vertexInput = GetVertexPositionInputs(vertex);
    output.positionCS = vertexInput.positionCS;
    output.positionWS.xyz = vertexInput.positionWS;
    output.positionWS.z = ComputeFogFactor(output.positionCS.z);

    output.normalWS = TransformObjectToWorldNormal(normalOS);
    output.tangentWS = TransformObjectToWorldDir(tangentOS);
    output.binormalWS = TransformObjectToWorldDir(binormalOS);

    #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
      output.shadowCoord = GetShadowCoord(vertexInput);
    #endif
    
    return output;
}

half4 Fragment (Varyings input) : SV_Target
{
    WaterSimulationSurfaceData surfData;
    InitializeWaterSimulationSurfaceData(input.uv, surfData);

    InputWaterData inputData;
    InitializeInputData(input, surfData.normalTS, inputData);

	BRDFBaseData brdfBaseData;
	InitializeWaterBRDFBaseData(surfData.albedo, surfData.metallic, half3(1, 1, 1), surfData.smoothness, surfData.alpha, brdfBaseData);

	Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, unity_ProbesOcclusion);
	
	InputDotData inputDotData;
	InitializeInputDotData(inputData, mainLight, inputDotData);
	
    half3 specular = GetMainSpecularColor(surfData, inputDotData, brdfBaseData);

	half3 finalColor = specular * mainLight.color + surfData.albedo;
    return half4(finalColor, surfData.alpha);
}

#endif


            
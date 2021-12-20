#ifndef WATERSIMULATION_INPUT
#define WATERSIMULATION_INPUT

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
#include "../ShaderLibrary/CustomLightingLib.hlsl"

CBUFFER_START(UnityPerMaterial)
    float4 _BaseColor;
    float _Metallic;
    float _Smoothness;

    float _Amplitude1;
    float _Speed1;
    float _WaveLength1;
    float4 _Direction1;
    float _Amplitude2;
    float _Speed2;
    float _WaveLength2;
    float4 _Direction2;
    float _Amplitude3;
    float _Speed3;
    float _WaveLength3;
    float4 _Direction3;
CBUFFER_END

struct WaterSimulationSurfaceData
{
    float3 albedo;
    float alpha;
    float3 normalTS;
    float metallic;
    float smoothness;
};

struct InputWaterData
{
    half4 positionWS;
    half3 normalWS;
    half3 viewDirectionWS;
    half4 shadowCoord;
    half fogCoord;
    half3 bakedGI;
};

struct InputDotData
{
    half NdotL;
    half NdotLClamp;
    half HalfLambert;
    half NdotV;
    half NdotH;
    half LdotH;
    half atten;
};


half4 SampleTexture(float2 uv,TEXTURE2D_PARAM(map, sampler_map))
{
    half4 mainTexCol = 0;
    mainTexCol= SAMPLE_TEXTURE2D(map,sampler_map, uv);
    return mainTexCol;
}


inline void InitializeWaterBRDFBaseData(half3 albedo, half metallic, half3 specular, half smoothness, half alpha, out BRDFBaseData outBRDFBaseData)
{

    half oneMinusReflectivity = LinearOneMinusReflectivityFromMetallic(metallic);
    half reflectivity = 1.0 - oneMinusReflectivity;

    outBRDFBaseData.diffuse = albedo * oneMinusReflectivity;
    outBRDFBaseData.specColor = lerp(unity_LinearColorSpaceDielectricSpec.rgb, albedo, metallic);

    outBRDFBaseData.grazingTerm = saturate(smoothness + reflectivity);
    outBRDFBaseData.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);
    // NB: CustomLit 使用的是HALF_MIN， 结果GGX在光滑度为1是很小
    outBRDFBaseData.roughness = max(PerceptualRoughnessToRoughness(outBRDFBaseData.perceptualRoughness), HALF_MIN_SQRT); 
    outBRDFBaseData.roughness2 = outBRDFBaseData.roughness * outBRDFBaseData.roughness;

    outBRDFBaseData.normalizationTerm = outBRDFBaseData.roughness * 4.0h + 2.0h;
    outBRDFBaseData.roughness2MinusOne = outBRDFBaseData.roughness2 - 1.0h;
}

inline void InitializeWaterSimulationSurfaceData(float2 uv, out WaterSimulationSurfaceData surfData)
{
    surfData = (WaterSimulationSurfaceData)0;
    
    #if _NORMALMAP
        half4 tangentNormal = SampleTexture(uv,TEXTURE2D_ARGS(_BumpMap,sampler_BumpMap));
        tangentNormal.xyz = UnpackNormalScale(tangentNormal, _BumpStrength);
        // 如果只是用法线的RG通道计算法线的话，可以使用该方法
        //tangentNormal.xyz = UnpackNormalRG(tangentNormal,_BumpStrength);
    #else
        half4 tangentNormal = half4(0.0h, 0.0h, 1.0h, 1.0h);
    #endif
    
    surfData.albedo = _BaseColor.rgb;
    surfData.normalTS = tangentNormal;
    surfData.alpha = _BaseColor.a;
    surfData.metallic = _Metallic;
    surfData.smoothness = _Smoothness;
}




#endif

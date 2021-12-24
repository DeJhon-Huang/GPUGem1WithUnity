#ifndef UNIVERSAL_SHIYUE_LIT_LIGHTINGLIB_INCLUDED
#define UNIVERSAL_SHIYUE_LIT_LIGHTINGLIB_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"
#include "AdditionalInput.hlsl"

#ifdef _CUSTOM_BOXPROJECTION
#include "../ShaderLibrary/BoxProjection.hlsl"
#endif


#ifdef _CUSTOM_ENV_CUBE
TEXTURECUBE(_EvnCubemap);  SAMPLER(sampler_EvnCubemap);
#elif _SCENE_ENV
TEXTURECUBE(_CharacterCustomEnv);  SAMPLER(sampler_CharacterCustomEnv); // 角色专用
#endif

//低配高光采样贴图
TEXTURE2D(unity_NHxRoughness); SAMPLER(samplerunity_NHxRoughness);

///////////////////////////////////////////////////////////////////////////////
//                         BRDF Functions                                    //
///////////////////////////////////////////////////////////////////////////////

struct BRDFBaseData
{
    half3 diffuse;
    half3 specColor;
    half  grazingTerm;
    half  perceptualRoughness;
    half  roughness;
    half  roughness2;

    // We save some light invariant BRDF terms so we don't have to recompute
    // them in the light loop. Take a look at DirectBRDF function for detailed explaination.
    half normalizationTerm;     // roughness * 4.0 + 2.0
    half roughness2MinusOne;    // roughness^2 - 1.0
};

#define unity_LinearColorSpaceDielectricSpec half4(0.04, 0.04, 0.04, 1.0 - 0.04) // standard dielectric reflectivity coef at incident angle (= 4%)

inline half LinearOneMinusReflectivityFromMetallic(half metallic)
{
    half oneMinusDielectricSpec = unity_LinearColorSpaceDielectricSpec.a;
    return oneMinusDielectricSpec - metallic * oneMinusDielectricSpec;
}

inline void InitializeBRDFBaseData(half3 albedo, half metallic, half3 specular, half smoothness, half alpha, out BRDFBaseData outBRDFBaseData)
{

    half oneMinusReflectivity = LinearOneMinusReflectivityFromMetallic(metallic);
    half reflectivity = 1.0 - oneMinusReflectivity;

    outBRDFBaseData.diffuse = albedo * oneMinusReflectivity;
    outBRDFBaseData.specColor = lerp(unity_LinearColorSpaceDielectricSpec.rgb, albedo, metallic);

    outBRDFBaseData.grazingTerm = saturate(smoothness + reflectivity);
    outBRDFBaseData.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);
    outBRDFBaseData.roughness = max(PerceptualRoughnessToRoughness(outBRDFBaseData.perceptualRoughness), HALF_MIN);
    outBRDFBaseData.roughness2 = outBRDFBaseData.roughness * outBRDFBaseData.roughness;

    outBRDFBaseData.normalizationTerm = outBRDFBaseData.roughness * 4.0h + 2.0h;
    outBRDFBaseData.roughness2MinusOne = outBRDFBaseData.roughness2 - 1.0h;

}

float3 RotateAround(float3 target, float degree)
{
    float rad = degree * 0.01745f;
    float2x2 m_rotate = float2x2(cos(rad), -sin(rad),
        sin(rad), cos(rad));
    float2 dir_rotate = mul(m_rotate, target.xz);
    target = float3(dir_rotate.x, target.y, dir_rotate.y);
    return target;
}

half3 EnvBRDFApprox( half3 SpecularColor, half Roughness, half NoV)
{
    const half4 c0 = { -1, -0.0275, -0.572, 0.022 };
    const half4 c1 = { 1, 0.0425, 1.04, -0.04 };
    half4 r = Roughness * c0 + c1;
    half a004 = min( r.x * r.x, exp2( -9.28 * NoV ) ) * r.x + r.y;
    half2 AB = half2( -1.04, 1.04 ) * a004 + r.zw;
    return SpecularColor * AB.x + AB.y;
}

half3 CustomEnvironmentBRDF(BRDFBaseData brdfData, half3 indirectDiffuse, half3 indirectSpecular, half fresnelTerm)
{
    half3 c = indirectDiffuse * brdfData.diffuse;
    float surfaceReduction = 1.0 / (brdfData.roughness2 + 1.0);
    c += surfaceReduction * indirectSpecular * lerp(brdfData.specColor, brdfData.grazingTerm, fresnelTerm);
    return c;
}

half3 CustomGlossyEnvironmentReflection(half3 reflectVector, half perceptualRoughness, half occlusion)
{
    // return 1;
    #if defined(_GLOSSYREFLECTIONS_ON)
        half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
        //half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip);
        #ifdef _CUSTOM_ENV_CUBE  
        half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(_EvnCubemap, sampler_EvnCubemap, reflectVector, mip);
        #else
        half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip);
        #endif
    
        #if !defined(UNITY_USE_NATIVE_HDR)
            half3 irradiance = DecodeHDREnvironment(encodedIrradiance, unity_SpecCube0_HDR);
        #else
            half3 irradiance = encodedIrradiance.rbg;
        #endif
        #if UNITY_COLORSPACE_GAMMA
        return irradiance.rgb = FastSRGBToLinear(irradiance.rgb);
        #endif
        return irradiance * occlusion;
    #endif // GLOSSY_REFLECTIONS
    //return encodedIrradiance.xyz
    return _GlossyEnvironmentColor.rgb * occlusion;
}


half3 CustomGlossyEnvironmentReflection(float3 positionWS,half3 reflectVector, half perceptualRoughness, half occlusion,AdditionalData boxData)
{
    #if defined(_GLOSSYREFLECTIONS_ON)
    half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
    #ifdef _CUSTOM_ENV_CUBE  
    #ifdef _CUSTOM_BOXPROJECTION
    reflectVector = BoxProjectionCubeMap(reflectVector,positionWS,boxData);
    #endif 
    half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(_EvnCubemap, sampler_EvnCubemap, reflectVector, mip);
    #else
    half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip);
    #endif
    #if !defined(UNITY_USE_NATIVE_HDR)
    // //注意，当场景LightingSetting 没有使用skybox 作为Environment Reflections 进行烘焙 时，unity_SpecCube0_HDR 的值是一个默认的值，如果这时候使用unity_SpecCube0_HDR，会导致结果错误
    // // 所以当我们使用_CUSTOM_ENV_CUBE 时，使用默认的时，unity_SpecCube0_HDR = half4(34.49324,2.2,0,1) 参数
      
    #ifdef _CUSTOM_ENV_CUBE
          half4 decodeInstructions = lerp(unity_SpecCube0_HDR,boxData.custom_SpecCube_HDR,boxData.use_Custom_HDR);
    #else
          half4 decodeInstructions =  unity_SpecCube0_HDR;
    #endif
    
    half3 irradiance = DecodeHDREnvironment(encodedIrradiance, decodeInstructions);
    #else
    half3 irradiance = encodedIrradiance.rgb;
    #endif
       
    #if UNITY_COLORSPACE_GAMMA
    return irradiance.rgb = FastSRGBToLinear(irradiance.rgb);
    #endif
    return irradiance * occlusion;
    #endif // GLOSSY_REFLECTIONS
    //return encodedIrradiance.xyz
    return _GlossyEnvironmentColor.rgb * occlusion;
}

half3 CustomGlobalIllumination(BRDFBaseData brdfData, half3 bakedGI, half occlusion, half EnvExposure, half3 normalWS, half3 viewDirectionWS)
{
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half fresnelTerm = Pow4(1.0 - saturate(dot(normalWS, viewDirectionWS)));
    half3 indirectDiffuse = bakedGI * occlusion;
    half3 indirectSpecular = CustomGlossyEnvironmentReflection(reflectVector, brdfData.perceptualRoughness, occlusion) * EnvExposure;
    return CustomEnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);
}

// ----------环境球旋转 + 自定义HDR系数-----------
half3 CustomGlossyEnvironmentReflectionAddData(half3 reflectVector, half perceptualRoughness, half occlusion, AdditionalData addData)
{
    // return 1;
    #if defined(_GLOSSYREFLECTIONS_ON)
    half mip = PerceptualRoughnessToMipmapLevel(perceptualRoughness);
    //half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip);
    #ifdef _CUSTOM_ENV_CUBE  
    half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(_EvnCubemap, sampler_EvnCubemap, reflectVector, mip);
    #else
    half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectVector, mip);
    #endif

    #ifdef _CUSTOM_ENV_CUBE
    half4 decodeInstructions = lerp(unity_SpecCube0_HDR,addData.custom_SpecCube_HDR,addData.use_Custom_HDR);
    #else
    half4 decodeInstructions =  unity_SpecCube0_HDR;
    #endif
    
    #if !defined(UNITY_USE_NATIVE_HDR)
    half3 irradiance = DecodeHDREnvironment(encodedIrradiance, decodeInstructions);
    #else
    half3 irradiance = encodedIrradiance.rbg;
    #endif
    #if UNITY_COLORSPACE_GAMMA
    return irradiance.rgb = FastSRGBToLinear(irradiance.rgb);
    #endif
    return irradiance * occlusion;
    #endif // GLOSSY_REFLECTIONS
    //return encodedIrradiance.xyz
    return _GlossyEnvironmentColor.rgb * occlusion;
}

half3 CustomGlobalIlluminationRotate(BRDFBaseData brdfData, half3 bakedGI, half occlusion, half EnvExposure, half3 normalWS, half3 viewDirectionWS, float envRotate, AdditionalData addData)
{
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half3 reflectRotaDir = RotateAround(reflectVector, envRotate);
    half fresnelTerm = Pow4(1.0 - saturate(dot(normalWS, reflectVector)));
    half3 indirectDiffuse = bakedGI * occlusion;
    half3 indirectSpecular = CustomGlossyEnvironmentReflectionAddData(reflectRotaDir, brdfData.perceptualRoughness, occlusion, addData) * EnvExposure;
    return CustomEnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);
}

half3 CustomGlobalIlluminationRotate(BRDFBaseData brdfData, half3 bakedGI, half occlusion, half EnvExposure, half3 normalWS, half3 viewDirectionWS, float envRotate)
{
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half3 reflectRotaDir = RotateAround(reflectVector, envRotate);
    half fresnelTerm = Pow4(1.0 - saturate(dot(normalWS, reflectVector)));
    half3 indirectDiffuse = bakedGI * occlusion;
    half3 indirectSpecular = CustomGlossyEnvironmentReflection(reflectRotaDir, brdfData.perceptualRoughness, occlusion) * EnvExposure;
    return CustomEnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);
}
// --------------------------------

// -------------- 角色专用

half3 CharacterGlobalIllumination(BRDFBaseData brdfData, half occlusion, half EnvExposure, half3 normalWS, half3 viewDirectionWS, float envRotate, AdditionalData addData)
{
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half3 reflectRotaDir = RotateAround(reflectVector, envRotate);
    half fresnelTerm = Pow4(1.0 - saturate(dot(normalWS, reflectVector)));
    half3 indirectSpecular = 0;

    // specular:
    #if defined(_GLOSSYREFLECTIONS_ON)
    half mip = PerceptualRoughnessToMipmapLevel(brdfData.perceptualRoughness);
    //half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectRotaDir, mip);
    #ifdef _CUSTOM_ENV_CUBE  
    half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(_EvnCubemap, sampler_EvnCubemap, reflectRotaDir, mip);
    #elif _SCENE_ENV
    half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(_CharacterCustomEnv, sampler_CharacterCustomEnv, reflectRotaDir, mip);
    #else
    half4 encodedIrradiance = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0, samplerunity_SpecCube0, reflectRotaDir, mip);
    #endif

    #if _CUSTOM_ENV_CUBE || _SCENE_ENV
    half4 decodeInstructions = lerp(unity_SpecCube0_HDR,addData.custom_SpecCube_HDR,addData.use_Custom_HDR);
    #else
    half4 decodeInstructions =  unity_SpecCube0_HDR;
    #endif
    
    #if !defined(UNITY_USE_NATIVE_HDR)
    half3 irradiance = DecodeHDREnvironment(encodedIrradiance, decodeInstructions);
    #else
    half3 irradiance = encodedIrradiance.rbg;
    #endif
    
    #if UNITY_COLORSPACE_GAMMA
    indirectSpecular =  irradiance.rgb = FastSRGBToLinear(irradiance.rgb);
    #endif
    indirectSpecular =  irradiance * occlusion;
    #else // GLOSSY_REFLECTIONS
    indirectSpecular =  _GlossyEnvironmentColor.rgb * occlusion;
    #endif
    indirectSpecular *= EnvExposure;
    
    float surfaceReduction = 1.0 / (brdfData.roughness2 + 1.0);
    return surfaceReduction * indirectSpecular * lerp(brdfData.specColor, brdfData.grazingTerm, fresnelTerm);
}

// ---------------------

half3 CustomGlobalIlluminationColor(BRDFBaseData brdfData,half occlusion, half EnvExposure ,half3 normalWS,half3 viewDirectionWS){
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half fresnelTerm = Pow4(1.0 - saturate(dot(normalWS, viewDirectionWS)));
    return CustomGlossyEnvironmentReflection(reflectVector, brdfData.perceptualRoughness, occlusion) * EnvExposure;
}

half3 CustomGlobalIlluminationColor(BRDFBaseData brdfData,half occlusion, half EnvExposure ,half3 normalWS,half3 viewDirectionWS,AdditionalData boxData){
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    //half fresnelTerm = Pow4(1.0 - saturate(dot(normalWS, viewDirectionWS)));
    return CustomGlossyEnvironmentReflection(boxData.positionWS,reflectVector, brdfData.perceptualRoughness, occlusion ,boxData) * EnvExposure;
}

half3 CustomBoxProjectionRefColor(BRDFBaseData brdfData,half occlusion, half EnvExposure ,half3 normalWS,half3 viewDirectionWS,AdditionalData  addData){
    #if defined(_CUSTOM_BOXREFRACT)
        half3 reflectVector = normalize( refract(-viewDirectionWS,normalWS,1.1));
    #else
    half3 reflectVector = normalize(reflect(-viewDirectionWS,normalWS)); 
#endif
        half fresnelTerm = Pow4(1.0 - saturate(dot(normalWS, viewDirectionWS)));
        return  CustomGlossyEnvironmentReflection(addData.positionWS,reflectVector,lerp(brdfData.perceptualRoughness,addData.boxRouness,addData.strength),occlusion,addData) * EnvExposure;

}

    half3 CustomEnvironmentBRDF(BRDFBaseData brdfData, half3 indirectDiffuse, half3 indirectSpecular, half fresnelTerm,AdditionalData addData)
    {
    half3 c = indirectDiffuse * brdfData.diffuse;
    float surfaceReduction = 1.0 /  (brdfData.roughness2 + 1.0);
    c += surfaceReduction * indirectSpecular *  lerp( lerp(brdfData.specColor,brdfData.grazingTerm,fresnelTerm),1,addData.strength);
    return c;
    }

half3 AdditionalCustomGlobalIllumination(BRDFBaseData brdfData,half3 bakedGI,half occlusion,half envExposure,InputData inputData,AdditionalData addData){
    half3 color =0;
    #ifdef _CUSTOM_BOXPROJECTION
        color =  CustomBoxProjectionRefColor(brdfData,occlusion,envExposure,inputData.normalWS,inputData.viewDirectionWS,addData);
    #else
        color =  CustomGlobalIlluminationColor(brdfData, occlusion, envExposure, inputData.normalWS, inputData.viewDirectionWS,addData);
    #endif  

    #if (_SAMPLER_PLANARTEX)
//        #if _ACTIVE_PLANARREF
            //  half mip = PerceptualRoughnessToMipmapLevel(brdfData.perceptualRoughness);// 效果非常拉
            color = BlendPlanarReflect(inputData.positionWS,inputData.normalWS,color,0);
//        #endif
    #endif
    
	half fresnelTerm = Pow4(1.0 - saturate(dot(inputData.normalWS,inputData.viewDirectionWS)));

    color =  CustomEnvironmentBRDF(brdfData,inputData.bakedGI * occlusion,color,fresnelTerm,addData);
    return color;
}



//GGX高光模型
//没了菲涅尔
half3 DirectBRDFShading(half nh, half nl,half lh,BRDFBaseData brdfData)
{
    // GGX Distribution multiplied by combined approximation of Visibility and Fresnel
    // BRDFspec = (D * V * F) / 4.0
    // D = roughness^2 / ( NoH^2 * (roughness^2 - 1) + 1 )^2
    // V * F = 1.0 / ( LoH^2 * (roughness + 0.5) )
    // See "Optimizing PBR for Mobile" from Siggraph 2015 moving mobile graphics course
    // https://community.arm.com/events/1155
    // Final BRDFspec = roughness^2 / ( NoH^2 * (roughness^2 - 1) + 1 )^2 * (LoH^2 * (roughness + 0.5) * 4.0)
    // We further optimize a few light invariant terms
    // brdfData.normalizationTerm = (roughness + 0.5) * 4.0 rewritten as roughness * 4.0 + 2.0 to a fit a MAD.
    float d = nh * nh * (brdfData.roughness2-1) + 1.00001f;
    half LoH2 = lh * lh;
    half specularTerm = brdfData.roughness2 / ((d * d) * max(0.1h, LoH2) *brdfData.normalizationTerm);
    // On platforms where half actually means something, the denominator has a risk of overflow
    // clamp below was added specifically to "fix" that, but dx compiler (we convert bytecode to metal/gles)
    // sees that specularTerm have only non-negative terms, so it skips max(0,..) in clamp (leaving only min(100,...))
    #if defined (SHADER_API_MOBILE) 
    specularTerm = specularTerm - HALF_MIN;
    specularTerm = clamp(specularTerm, 0.0, 100.0); // Prevent FP16 overflow on mobiles
    #endif
    half3 color = specularTerm * brdfData.specColor;
    return color;
}

half DirectBRDFShading_UE4(half nh, half nl,half lh,BRDFBaseData brdfData)
{
    // GGX Distribution multiplied by combined approximation of Visibility and Fresnel
    // BRDFspec = (D * V * F) / 4.0
    // D = roughness^2 / ( NoH^2 * (roughness^2 - 1) + 1 )^2
    // V * F = 1.0 / ( LoH^2 * (roughness + 0.5) )
    // See "Optimizing PBR for Mobile" from Siggraph 2015 moving mobile graphics course
    // https://community.arm.com/events/1155
    // Final BRDFspec = roughness^2 / ( NoH^2 * (roughness^2 - 1) + 1 )^2 * (LoH^2 * (roughness + 0.5) * 4.0)
    // We further optimize a few light invariant terms
    // brdfData.normalizationTerm = (roughness + 0.5) * 4.0 rewritten as roughness * 4.0 + 2.0 to a fit a MAD.
    float d = nh * nh * (brdfData.roughness2-1) + 1.00001f;
    half LoH2 = lh * lh;
    //half specularTerm = brdfData.roughness2 / ((d * d) * max(0.1h, LoH2) *brdfData.normalizationTerm);
    half specularTerm = brdfData.roughness2 / (PI * (d * d));
    // On platforms where half actually means something, the denominator has a risk of overflow
    // clamp below was added specifically to "fix" that, but dx compiler (we convert bytecode to metal/gles)
    // sees that specularTerm have only non-negative terms, so it skips max(0,..) in clamp (leaving only min(100,...))
    #if defined (SHADER_API_MOBILE) 
    specularTerm = specularTerm - HALF_MIN;
    specularTerm = clamp(specularTerm, 0.0, 100.0); // Prevent FP16 overflow on mobiles
    #endif
    return specularTerm ;
}


half3 Direct_BRDF(BRDFBaseData brdfdata,half3 lightColor, half3 lightDirectionWS,half lightAttenuation,half3 shadowColor,  half3 normalWS, half3 viewDirectionWS)
{
    half NdotL = saturate(dot(normalWS, lightDirectionWS));

    half3 radiance = lightColor * (lightAttenuation * NdotL);

    half3 color = brdfdata.diffuse;
    #if _SPECULARHIGHLIGHTS_ON
        #ifndef _NHxRoughness
            float3 halfDir = SafeNormalize(float3(lightDirectionWS) + float3(viewDirectionWS));
            float  NdotH   = saturate(dot(normalWS, halfDir));
            half   LdotH   = saturate(dot(lightDirectionWS, halfDir));
            color += DirectBRDFShading(NdotH,NdotL,LdotH,brdfdata);
        #else
            half3 reflDir = reflect(-viewDirectionWS,normalWS);
            half  rdotl  =saturate(dot(reflDir,lightDirectionWS));
            half  rlPow4 = (rdotl*rdotl) * (rdotl*rdotl);
            half LUT_RANGE = 16.0; // must match range in NHxRoughness() function in GeneratedTextures.cpp
            half specular = SAMPLE_TEXTURE2D(unity_NHxRoughness,samplerunity_NHxRoughness,float2(rlPow4,brdfdata.roughness));
            specular *= LUT_RANGE;
            color += specular; 
        #endif
    #endif
    #ifdef SHADOWCOLOR
    radiance = lerp(shadowColor,half3(1.0h,1.0h,1.0h),radiance);
    #endif
    return color * radiance;
}

half3 Direct_BRDF(BRDFBaseData brdfdata,Light light,half3 shadowColor,half3 normalWS, half3 viewDirectionWS)
{
    return Direct_BRDF(brdfdata,light.color,light.direction, light.distanceAttenuation * light.shadowAttenuation,shadowColor,normalWS,viewDirectionWS);
}

#if defined(_DEBUG)
#include "../Debug/InputDebug.hlsl"
#include "../Debug/PBRDataDebug.hlsl"
#endif


    ///////////////////////////////////////////////////////////////////////////////
    //                      Fragment Functions                                   //
    //       Used by ShaderGraph and others builtin renderers                    //
    ///////////////////////////////////////////////////////////////////////////////
half4 FragmentPBRShading(InputData inputData, half3 albedo, half metallic, half3 specular, half3 shadowColor,
    half smoothness, half occlusion, half envExposure, half3 emission, half alpha)
{
    BRDFBaseData brdfData;
    InitializeBRDFBaseData(albedo, metallic, specular, smoothness, alpha, brdfData);
    /* Shadowmask implementation start */
    // To ensure backward compatibility we have to avoid using shadowMask input, as it is not present in older shaders
    #if defined(SHADOWS_SHADOWMASK) && defined(LIGHTMAP_ON)
        half4 shadowMask = inputData.shadowMask;
    #elif !defined (LIGHTMAP_ON)
        half4 shadowMask = unity_ProbesOcclusion;
    #else
        half4 shadowMask = half4(1, 1, 1, 1);
    #endif
    /* Shadowmask implementation end */
    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, shadowMask);
    //MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);
    half3 color =  CustomGlobalIllumination(brdfData, inputData.bakedGI, occlusion, envExposure, inputData.normalWS, inputData.viewDirectionWS);
    color += Direct_BRDF(brdfData, mainLight, shadowColor, inputData.normalWS, inputData.viewDirectionWS);
    //多灯光
#ifdef _ADDITIONAL_LIGHTS
    uint pixelLightCount = GetAdditionalLightsCount();
    for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
    {
        /* Shadowmask implementation start */
        Light light = GetAdditionalLight(lightIndex, inputData.positionWS, shadowMask);
        /* Shadowmask implementation end */
        color += Direct_BRDF(brdfData, light, shadowColor, inputData.normalWS, inputData.viewDirectionWS);
    }
#endif
#ifdef _ADDITIONAL_LIGHTS_VERTEX
    color += inputData.vertexLighting * brdfData.diffuse;
#endif
    color += emission;
    return half4(color, alpha);
}


// 启用额外处理Fragment
half4 FragmentPBRShading(InputData inputData, half3 albedo, half metallic, half3 specular, half3 shadowColor,
    half smoothness, half occlusion, half envExposure, half3 emission, half alpha,AdditionalData addData)
{
    BRDFBaseData brdfData;
    InitializeBRDFBaseData(albedo, metallic, specular, smoothness, alpha, brdfData);
    /* Shadowmask implementation start */
    // To ensure backward compatibility we have to avoid using shadowMask input, as it is not present in older shaders
    #if defined(SHADOWS_SHADOWMASK) && defined(LIGHTMAP_ON)
        half4 shadowMask = inputData.shadowMask;
    #elif !defined (LIGHTMAP_ON)
        half4 shadowMask = unity_ProbesOcclusion;
    #else
        half4 shadowMask = half4(1, 1, 1, 1);
    #endif
    //GL计算
    /* Shadowmask implementation end */
    //MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);
    //CustomGlobalIllumination 拆分 3 种情况
    // 1-无boxProjectin
    // 2-boxProjection
    // 3-PlanarRef
    // 然后再进行CustomEnviornmentBRDF
    half3 color = AdditionalCustomGlobalIllumination(brdfData,inputData.bakedGI,occlusion,envExposure,inputData,addData);

    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, shadowMask);
    color += Direct_BRDF(brdfData, mainLight, shadowColor, inputData.normalWS, inputData.viewDirectionWS);

    //多灯光
    #ifdef _ADDITIONAL_LIGHTS
        uint pixelLightCount = GetAdditionalLightsCount();
        for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
        {
            /* Shadowmask implementation start */
            Light light = GetAdditionalLight(lightIndex, inputData.positionWS, shadowMask);
            /* Shadowmask implementation end */
            color += Direct_BRDF(brdfData, light, shadowColor, inputData.normalWS, inputData.viewDirectionWS);
        }
    #endif

    #ifdef _ADDITIONAL_LIGHTS_VERTEX
        color += inputData.vertexLighting * brdfData.diffuse;
    #endif

    color += emission;

    #if defined(_DEBUG)
    half3 result = color.rgb;
    bool needLinearToSRGB = false;
    GetBRDFataDebug(debugMode,brdfData,result,needLinearToSRGB);
    GetGlobalIlluminationDataDebug(debugMode,brdfData,inputData.bakedGI,occlusion,envExposure,inputData,addData,result,needLinearToSRGB);
    color.rgb = result;
    #endif

    return half4(color, alpha);
}




half3 FastSubsurfaceTranslucency(half3 lightColor,half lightAttenuation,half3 shadowColor,half maskValue,half transmission,half3 scatterColor  )
{
    half SSSTransmission= transmission * maskValue;
    half3 sssIntensity = max((scatterColor* SSSTransmission +shadowColor)/(scatterColor * SSSTransmission + 1),0);
    return lightAttenuation * sssIntensity * lightColor;
}

half4 FragmentWZRYPBRShading(InputData inputData, half3 albedo, half metallic, half3 specular, half3 shadowColor,
    half smoothness, half occlusion, half envExposure, half3 emission, half alpha, half sssTransmission, half3 sssscatterColor)
{
    BRDFBaseData brdfData;
    InitializeBRDFBaseData(albedo, metallic, specular, smoothness, alpha, brdfData);

    /* Shadowmask implementation start */
    //MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI, half4(0, 0, 0, 0));
    // To ensure backward compatibility we have to avoid using shadowMask input, as it is not present in older shaders
    #if defined(SHADOWS_SHADOWMASK) && defined(LIGHTMAP_ON)
        half4 shadowMask = inputData.shadowMask;
    #elif !defined (LIGHTMAP_ON)
        half4 shadowMask = unity_ProbesOcclusion;
    #else
        half4 shadowMask = half4(1, 1, 1, 1);
    #endif
    /* Shadowmask implementation end */
    Light mainLight = GetMainLight(inputData.shadowCoord, inputData.positionWS, shadowMask);
    //MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI, half4(0, 0, 0, 0));
    half3 color = CustomGlobalIllumination(brdfData, inputData.bakedGI, occlusion, envExposure, inputData.normalWS, inputData.viewDirectionWS);
    half3 subcolor = FastSubsurfaceTranslucency(mainLight.color, mainLight.distanceAttenuation * mainLight.shadowAttenuation, shadowColor, emission.x, sssTransmission, sssscatterColor);
    color += Direct_BRDF(brdfData, mainLight, subcolor, inputData.normalWS, inputData.viewDirectionWS);

    //多灯光
#ifdef _ADDITIONAL_LIGHTS
    uint pixelLightCount = GetAdditionalLightsCount();
    for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
    {
        /* Shadowmask implementation start */
        Light light = GetAdditionalLight(lightIndex, inputData.positionWS, shadowMask);
        /* Shadowmask implementation end */
        half NdotL = saturate(dot(inputData.normalWS, light.direction));
        half3 addsubcolor = FastSubsurfaceTranslucency(mainLight.color, mainLight.distanceAttenuation * mainLight.shadowAttenuation, NdotL.xxx, emission.x, sssTransmission, sssscatterColor);
        half3 addColor = Direct_BRDF(brdfData, light, addsubcolor, inputData.normalWS, inputData.viewDirectionWS);

        color += addColor;
    }
#endif
#ifdef _ADDITIONAL_LIGHTS_VERTEX
    color += inputData.vertexLighting * brdfData.diffuse;
#endif
    //color += emission;
    return half4(color, alpha);
}

#endif

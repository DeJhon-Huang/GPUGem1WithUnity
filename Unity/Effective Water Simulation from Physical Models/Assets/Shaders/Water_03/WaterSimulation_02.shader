Shader "Rookie/GPUGem/01-WaterSimulator_Circle"
{
    Properties
    {
    	[Header(Base)]
    	_BaseColor ("Base Color", Color) = (1,1,1,1)
    	_Metallic ("Metallic", Range(0,1)) = 0
    	_Smoothness ("Smoothness", Range(0,1)) = 0.5
        
        [Header(Wave1)]
        _Amplitude1("振幅", Range(0,1)) = 0.5
        _Speed1("速度", Range(0,1)) = 0.5
        _WaveLength1("波长", Range(0,1)) = 0.5
        _Direction1("方向", Vector) = (0,1,0,0)
         [Header(Wave2)]
        _Amplitude2("振幅", Range(0,1)) = 0.5
        _Speed2("速度", Range(0,1)) = 0.5
        _WaveLength2("波长", Range(0,1)) = 0.5
        _Direction2("方向", Vector) = (0,1,0,0)
         [Header(Wave3)]
        _Amplitude3("振幅", Range(0,1)) = 0.5
        _Speed3("速度", Range(0,1)) = 0.5
        _WaveLength3("波长", Range(0,1)) = 0.5
        _Direction3("方向", Vector) = (0,1,0,0)
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" "IgnoreProjector" = "True"
        }

        Pass
        {
            Blend srcAlpha OneMinusSrcAlpha
            
            Name "ForwardLit"
            Tags
            {
                "LightMode" = "UniversalForward"
            }
            
            HLSLPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment
            
            #pragma shader_feature _ _MAIN_LIGHT_SHADOWS
            #pragma shader_feature _ _SHADOWS_SOFT

            #include "WaterSimulation_Input.hlsl"
            #include "WaterSimulation_ForwardPass.hlsl"

            ENDHLSL
        }
    }
}
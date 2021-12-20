#ifndef			ADDITIONALINPUT
#define 		ADDITIONALINPUT

//额外数据入口
struct AdditionalData {
	half3 positionWS;
	// 盒装投影用参数
	// #ifdef _CUSTOM_BOXPROJECTION
	half4 boxCenter;
	half4 boxMax;
	half4 boxMin;
	half boxRouness;
	half strength;
	// #endif
	#if _CUSTOM_ENV_CUBE || _SCENE_ENV
	half use_Custom_HDR;
	half4 custom_SpecCube_HDR;
	#endif
};

// #ifdef _CUSTOM_BOXPROJECTION 
// AdditionalData InitBoxData(half4 boxCenter,half4 boxSize,half boxRouness,half  strength, AdditionalData data){
// 	data.boxCenter = boxCenter;
// 	data.boxMax  = boxCenter + boxSize*0.5;
// 	data.boxMin  = boxCenter - boxSize*0.5;
// 	data.boxRouness = abs(boxRouness-1);
// 	data.strength = (strength);
// //	data.positionWS = data.positionWS;
// 	return data;
// }
// #endif


void InitBoxData(half4 boxCenter,half4 boxSize,half boxRouness,half  strength,inout AdditionalData data)
{
	#ifdef _CUSTOM_BOXPROJECTION
		data.boxCenter = boxCenter;
		data.boxMax  = boxCenter + boxSize*0.5;
		data.boxMin  = boxCenter - boxSize*0.5;
		data.boxRouness = abs(boxRouness-1);
		data.strength = (strength);
	#endif
}

void InitHDRData(half use_Custom_HDR,half4 Custom_SpecCube_HDR,inout AdditionalData data)
{
	#if _CUSTOM_ENV_CUBE || _SCENE_ENV
		data.use_Custom_HDR = use_Custom_HDR;
		data.custom_SpecCube_HDR = Custom_SpecCube_HDR;
	#endif
}

#endif
#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ARR_3D_TYPE_DEF(name, type) typedef struct { \
    type* data; \
    size_t z;   \
    size_t y;   \
    size_t x;   \
} name;

#define ARR_2D_TYPE_DEF(name, type) typedef struct { \
    type* data; \
    size_t y;   \
    size_t x;   \
} name;

ARR_3D_TYPE_DEF(f32_arr_3d_t, float);
ARR_2D_TYPE_DEF(f32_arr_2d_t, float);
ARR_3D_TYPE_DEF(u16_arr_3d_t, uint16_t);
ARR_2D_TYPE_DEF(u16_arr_2d_t, uint16_t);
ARR_3D_TYPE_DEF(u8_arr_3d_t, uint8_t);
ARR_2D_TYPE_DEF(u8_arr_2d_t, uint8_t);

ARR_3D_TYPE_DEF(c_f32_arr_3d_t, const float);
ARR_2D_TYPE_DEF(c_f32_arr_2d_t, const float);
ARR_3D_TYPE_DEF(c_u16_arr_3d_t, const uint16_t);
ARR_2D_TYPE_DEF(c_u16_arr_2d_t, const uint16_t);
ARR_3D_TYPE_DEF(c_u8_arr_3d_t, const uint8_t);
ARR_2D_TYPE_DEF(c_u8_arr_2d_t, const uint8_t);

#ifdef __cplusplus
}
#endif
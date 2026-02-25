// kernel.cu
#include <stdint.h>
#include <cuda_bf16.h>

// =====================
// int16 kernels
// Each thread handles one element (i = threadIdx.x)
// Your architecture can map threadIdx.x however you want (e.g., sequential loop or SIMD lanes).
// =====================

// Vector Add: out[i] = a[i] + b[i]
extern "C" __global__ void vec_add_i16(const int16_t* a,
                                      const int16_t* b,
                                      int16_t* out,
                                      int n)
{
    int i = (int)threadIdx.x;
    if (i < n) out[i] = (int16_t)(a[i] + b[i]);
}
// ld.global.s16
// ld.global.s16
// add.s16
// st.global.s16

// Vector Sub: out[i] = a[i] - b[i]
extern "C" __global__ void vec_sub_i16(const int16_t* a,
                                      const int16_t* b,
                                      int16_t* out,
                                      int n)
{
    int i = (int)threadIdx.x;
    if (i < n) out[i] = (int16_t)(a[i] - b[i]);
}
// ld.global.s16
// ld.global.s16
// sub.s16
// st.global.s16

// ReLU on int16: out[i] = max(0, in[i])
extern "C" __global__ void relu_i16(const int16_t* in,
                                   int16_t* out,
                                   int n)
{
    int i = (int)threadIdx.x;
    if (i < n) {
        int16_t x = in[i];
        out[i] = (x > 0) ? x : (int16_t)0;
    }
}
// setp.gt.s16
// selp.s16
// max.s16

// =====================
// BF16 kernels
// Use __nv_bfloat16
// =====================

// BF16 Multiply: out[i] = a[i] * b[i]
extern "C" __global__ void vec_mul_bf16(const __nv_bfloat16* a,
                                       const __nv_bfloat16* b,
                                       __nv_bfloat16* out,
                                       int n)
{
    int i = (int)threadIdx.x;
    if (i < n) {
        // BF16 multiply
        out[i] = __hmul(a[i], b[i]);   // NVCC usually lowers this to BF16 ops
    }
}
// mul.bf16


// BF16 FMA/MAC: out[i] = out[i] + a[i] * b[i]
extern "C" __global__ void fma_bf16(const __nv_bfloat16* a,
                                   const __nv_bfloat16* b,
                                   __nv_bfloat16* out,
                                   int n)
{
    int i = (int)threadIdx.x;
    if (i < n) {
        // out = out + a*b
        // __hfma exists for half; for bf16, nvcc may use mma/fma sequences.
        // This pattern forces multiply+add close together for your parser mapping.
        __nv_bfloat16 prod = __hmul(a[i], b[i]);
        out[i] = __hadd(out[i], prod);
    }
}


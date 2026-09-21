#ifndef MATMUL_H
#define MATMUL_H

#include <hls_stream.h>
#include <ap_axi_sdata.h>
#include <ap_int.h>
#include <ap_fixed.h>

// Define maximum matrix size (up to 64x64 as per project spec)
#define MAX_SIZE 64
#define DATA_WIDTH 24

// Data type (float for easy comparison with numpy)
typedef ap_fixed<24,14> data_t;   //24,14 pretty good +-1 error
//CHANGE ABOVE DATA_T FOR ANY OTHER FIXED POINT WIDTHS, ALSO CHANGE DATA_WIDTH CONSTANT.
//CHANGE DATA_T TO 16,2 TO SEE REDUCED BRAM USAGE

// 32-bit AXI-Stream packet with TLAST signal
typedef ap_axis<32, 1, 1, 1> axis_pkt_t;

/* ---------- float <-> ap_int<32> conversion ---------- */
union float_bits {
    float    f;
    unsigned u;
};

static inline data_t unpack(ap_int<32> raw) {
    data_t val;
    val.range() = raw.range(DATA_WIDTH - 1, 0);
    return val;
}

static inline ap_int<32> pack(data_t val) {
	ap_int<32> raw = 0;
	raw.range(DATA_WIDTH - 1, 0) = val.range();
	return raw;
}

/* ---------- Function Prototype ---------- */
void matmul_stream(
    data_t A[MAX_SIZE][MAX_SIZE],
    hls::stream<axis_pkt_t> &in_stream,
    hls::stream<axis_pkt_t> &out_stream,
    int rows,
    int cols,
    int num_vectors
);

#endif

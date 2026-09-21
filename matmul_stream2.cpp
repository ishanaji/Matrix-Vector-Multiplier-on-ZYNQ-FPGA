#include "matmul.h"

void matmul_stream(
    data_t A[MAX_SIZE][MAX_SIZE],
    hls::stream<axis_pkt_t> &in_stream,
    hls::stream<axis_pkt_t> &out_stream,
    int rows,
    int cols,
    int num_vectors // How many x vectors to process
) {
#pragma HLS INTERFACE s_axilite port=A bundle=control
#pragma HLS INTERFACE s_axilite port=rows bundle=control
#pragma HLS INTERFACE s_axilite port=cols bundle=control
#pragma HLS INTERFACE s_axilite port=num_vectors bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

#pragma HLS INTERFACE axis port=in_stream
#pragma HLS INTERFACE axis port=out_stream

    data_t x_local[MAX_SIZE];
    
#pragma HLS ARRAY_PARTITION variable=x_local complete
#pragma HLS ARRAY_PARTITION variable=A dim=2 complete
//#pragma HLS ARRAY_PARTITION variable=x_local type=cyclic factor=4		//UNCOMMENT THESE AND COMMENT THE ABOVE FOR UNROLLED FACTOR 4 IMPLEMENTATION
//#pragma HLS ARRAY_PARTITION variable=A dim=2 type=cyclic factor=4
    batch_loop:
    for (int v = 0; v < num_vectors; v++) {

        // Read the current x vector
        read_x:
        for (int i = 0; i < cols; i++) {
#pragma HLS LOOP_TRIPCOUNT min=64 max=64
#pragma HLS PIPELINE II=1
            axis_pkt_t in_pkt = in_stream.read();
            x_local[i] = unpack(in_pkt.data);
        }

        // Compute y = A * x and stream it out
        compute_y:
        for (int i = 0; i < rows; i++) {
#pragma HLS LOOP_TRIPCOUNT min=64 max=64
#pragma HLS PIPELINE II=1	//turn off for unrolled factor 4 and baseline implementations
            
            data_t acc = 0.0f;

            dot_product:
            for (int j = 0; j < MAX_SIZE; j++) {
#pragma HLS UNROLL	//GIVE FACTOR=4 FOR UNROLLED IMPLEMENTATION
                if (j < cols) {
                    acc += A[i][j] * x_local[j];
                }
            }

            axis_pkt_t out_pkt;
            out_pkt.data = pack(acc);
            out_pkt.keep = -1;
            out_pkt.strb = -1;
            out_pkt.user = 0;
            out_pkt.id   = 0;
            out_pkt.dest = 0;
            
            // set TLAST=1 if it is the last row OF the last vector
            if ((v == num_vectors - 1) && (i == rows - 1)) {
                out_pkt.last = 1;
            } else {
                out_pkt.last = 0;
            }

            out_stream.write(out_pkt);
        }
    }
}

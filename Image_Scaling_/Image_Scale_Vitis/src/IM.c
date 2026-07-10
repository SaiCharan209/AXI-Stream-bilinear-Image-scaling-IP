#include "xparameters.h"
#include "xaxivdma.h"
#include "xil_cache.h"
#include "xil_printf.h"

#define W_IN         800
#define H_IN         566
#define W_OUT        900
#define H_OUT        700
#define PIXEL_BYTES  3

#define SRC_FRAME_ADDR  0x10000000  // Where we upload the input image via JTAG
#define DST_FRAME_ADDR  0x20000000  // Where we download the scaled image from

#define TIMEOUT_LOOPS   5000000      // generous, but now a REAL upper bound

XAxiVdma VdmaInstance;

static int WaitForChannelHalt(XAxiVdma *InstancePtr, u16 Direction, const char *Name) {
    int i;
    for (i = 0; i < TIMEOUT_LOOPS; i++) {
        if (!XAxiVdma_IsBusy(InstancePtr, Direction)) {
            xil_printf("%s channel completed after %d poll iterations.\n\r", Name, i);
            return 0;
        }
    }
    xil_printf("!!! TIMEOUT waiting for %s channel to halt !!!\n\r", Name);
    return -1;
}

int main() {
    int Status;

    xil_printf("\n\r--- ZCU104 Scaler Pipeline Armed ---\n\r");

    // 1. Initialize the VDMA instance
    XAxiVdma_Config *Config = XAxiVdma_LookupConfig(XPAR_AXIVDMA_0_DEVICE_ID);
    Status = XAxiVdma_CfgInitialize(&VdmaInstance, Config, Config->BaseAddress);
    if (Status != XST_SUCCESS) {
        xil_printf("VDMA config init failed: %d\n\r", Status);
        return XST_FAILURE;
    }

    // 2. Configure Read Channel (Memory -> Scaler IP)
    XAxiVdma_DmaSetup ReadCfg;
    ReadCfg.VertSizeInput       = H_IN;
    ReadCfg.HoriSizeInput       = W_IN * PIXEL_BYTES;
    ReadCfg.Stride              = W_IN * PIXEL_BYTES;
    ReadCfg.FrameDelay          = 0;
    ReadCfg.EnableCircularBuf   = 0;   // Single-frame transfer mode
    ReadCfg.EnableSync          = 0;   // Independent Master mode
    ReadCfg.PointNum            = 0;
    ReadCfg.EnableFrameCounter  = 0;
    ReadCfg.FixedFrameStoreAddr = 0;
    XAxiVdma_DmaConfig(&VdmaInstance, XAXIVDMA_READ, &ReadCfg);

    UINTPTR src_addr = SRC_FRAME_ADDR;
    XAxiVdma_DmaSetBufferAddr(&VdmaInstance, XAXIVDMA_READ, &src_addr);

    // 3. Configure Write Channel (Scaler IP -> Memory)
    XAxiVdma_DmaSetup WriteCfg;
    WriteCfg.VertSizeInput       = H_OUT;
    WriteCfg.HoriSizeInput       = W_OUT * PIXEL_BYTES;
    WriteCfg.Stride              = W_OUT * PIXEL_BYTES;
    WriteCfg.FrameDelay          = 0;
    WriteCfg.EnableCircularBuf   = 0;
    WriteCfg.EnableSync          = 0;
    WriteCfg.PointNum            = 0;
    WriteCfg.EnableFrameCounter  = 0;
    WriteCfg.FixedFrameStoreAddr = 0;
    XAxiVdma_DmaConfig(&VdmaInstance, XAXIVDMA_WRITE, &WriteCfg);

    UINTPTR dst_addr = DST_FRAME_ADDR;
    XAxiVdma_DmaSetBufferAddr(&VdmaInstance, XAXIVDMA_WRITE, &dst_addr);


    XAxiVdma_StartFrmCntEnable(&VdmaInstance, XAXIVDMA_READ);
    XAxiVdma_StartFrmCntEnable(&VdmaInstance, XAXIVDMA_WRITE);

    // 4. Critical Cache Management
    Xil_DCacheFlushRange(SRC_FRAME_ADDR, (W_IN * H_IN * PIXEL_BYTES));
    Xil_DCacheInvalidateRange(DST_FRAME_ADDR, (W_OUT * H_OUT * PIXEL_BYTES));

    xil_printf("Registers configured. Triggering VDMA engines...\n\r");

    // 5. Fire the hardware triggers (Write channel MUST be armed first)
    XAxiVdma_DmaStart(&VdmaInstance, XAXIVDMA_WRITE);
    XAxiVdma_DmaStart(&VdmaInstance, XAXIVDMA_READ);

    // 6. Wait for the Write channel to genuinely halt (now a valid check)
    if (WaitForChannelHalt(&VdmaInstance, XAXIVDMA_WRITE, "S2MM (write)") != 0) {
        u32 s2mm_sr = XAxiVdma_GetStatus(&VdmaInstance, XAXIVDMA_WRITE);
        xil_printf("S2MM_VDMASR (Status Reg): 0x%08x\n\r", (unsigned int)s2mm_sr);
        return XST_FAILURE;
    }

    u32 s2mm_sr_final = XAxiVdma_GetStatus(&VdmaInstance, XAXIVDMA_WRITE);
    xil_printf("Final S2MM_VDMASR: 0x%08x\n\r", (unsigned int)s2mm_sr_final);
    // Invalidate cache one last time to ensure coherence
    Xil_DCacheInvalidateRange(DST_FRAME_ADDR, (W_OUT * H_OUT * PIXEL_BYTES));
    xil_printf("--- SUCCESS: Scaled frame written to 0x20000000 ---\n\r");

    // Infinite loop to freeze the CPU so memory stays perfectly static for download
    while (1);
    return 0;
}


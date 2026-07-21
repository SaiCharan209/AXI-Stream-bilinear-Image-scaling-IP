# AXI-Stream-bilinear-Image-scaling-IP on Zynq Ultrascale FPGA

Designed a 6-stage bilinear image scaling pipeline and streaming the image using line buffers method reducing the memory utilization.
Successfully verified on zynq Ultrscale + FPGA SOC with minimal resource utilization.

---

## Key Design Features

- **3-line buffer architecture** <br>
  Used a 3 line buffer architecture for image streaming using AXI-4 stream which reduces the on-chip memory utilization compared to full frame buffering.

- **output FIFO** <br>
  Used output FIFO buffers to avoid stalling of the image pipeline if the DMA is slowing processing the data to the memory again.

- **Video Direct memory access** <br>
  we use VDMA to stream the data from the DDR memory in the Zynq UltraScale FPGA because the normal DMA doesn't know where the row ends ,but VDMA streams the image data as a row wise packet compared to DMA which sends the data as a whole packet as it doesn't recognise image and data separately.

- **Fixed point arithmetic for bilinear interpolation** <br>
  used 8 bit fractional part for good accuracy in the pixel intensity values and using lesser hardware for image scaling.
  
---

## Architecture Overview
Used AXI VDMA and internal FIFOs to ensure precise streaming of the image to the IP for bilinear scaling, the output FIFO is to maintain the speed of the IP, as most of the time the writing speed of the IP is more than the reading speed of the VDMA , so it is important to buffer the data if not stalls will occur in the pipeline due to which there would be a lot of time loss in the design.

![Architecture](Block_design_IMS.png)

## Synthesis and timing reports
Here as you can see the utilization reduced drastically for a 870 x 566 image and streaming it through the line buffer , as the BRAM usage is very less according to the image size we are using.

![Synthesis](Synthesis_report.png)

## DMA (Direct memory access)
Here the main architecture we used is DMA , by which without any CPU intervention we can directly fetch data from the DDR RAM and also write to it, in the absence of DMA if CPU communicates with the memory for fetching it would give so many idle cycles for the CPU not moving to the next instruction, if we use DMA the CPU can do the other instructions in the mean time and there would almost no idle cycles, which is the main advantage of DMA architecture.

![DMA](DMA.png)

## Testing and verification
Verified the design by deploying it on Zynq ultrascale+ ZCU104 FPGA Soc and successfully verified the scaled output with the simulated output. Max clock frequency at which the design can run is about 330 Mhz which corresponds to a impressive 400 fps video streaming which is industry standard in high quality cameras.

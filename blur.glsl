#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Storage buffer for the image data (RGBA pixels as uint)
layout(set = 0, binding = 0, std430) buffer MyDataBuffer {
	uint data[];  // Each uint contains 4 bytes (RGBA packed)
} my_data_buffer;

layout(push_constant) uniform PushConstants {
	uint width;
	uint height;
} push_constants;

void main() {
	uint x = gl_GlobalInvocationID.x;
	uint y = gl_GlobalInvocationID.y;
	
	if (x >= push_constants.width || y >= push_constants.height) return;

	uint pixel_idx = y * push_constants.width + x;
	
	// Ensure we don't access out of bounds
	if (pixel_idx >= my_data_buffer.data.length()) return;

	uint pixel = my_data_buffer.data[pixel_idx];
	uint r = (pixel >> 0)  & 0xFF;
	uint g = (pixel >> 8)  & 0xFF;
	uint b = (pixel >> 16) & 0xFF;
	
	uint sum_a = 0;
	uint count = 0;
	
	for (int dx = -1; dx <= 1; dx++) {
		for (int dy = -1; dy <= 1; dy++) {
			int nx = int(x) + dx;
			int ny = int(y) + dy;
			
			if (nx >= 0 && nx < int(push_constants.width) && ny >= 0 && ny < int(push_constants.height)) {
				uint neighbor_idx = ny * push_constants.width + nx;
				uint neighbor_pixel = my_data_buffer.data[neighbor_idx];
				
				sum_a += (neighbor_pixel >> 24) & 0xFF;
				count++;
			}
		}
	}
	
	// Average the Alpha values
	uint a = sum_a / count;
	
	// Modify only the Alpha channel
	if (a > 5) {
		a -= 5;
	} else {
		a = 0;
	}
	
	// Reconstruct the uint from modified RGBA components
	my_data_buffer.data[pixel_idx] = (r << 0) | (g << 8) | (b << 16) | (a << 24);
	
	// Ensure all invocations finish writing before the shader ends
	memoryBarrier();
}

#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// Storage buffer for agent data
layout(set = 0, binding = 0, std430) buffer AgentBuffer {
	float data[]; // Each agent has (x, y, angle)
} agent_buffer;

layout(set = 0, binding = 1, std430) buffer ReadBuffer {
	uint data[]; //used for trail detection
} read_buffer;

layout(set = 0, binding = 2, std430) buffer WriteBuffer {
	uint data[]; //used for setting the agents pos. alpha to max
} write_buffer;

layout(push_constant) uniform PushConstants {
	float speed;
	uint agent_count;
	uint width;
	uint height;
} push_constants;

// Function to generate random float from a seed (simple hash-based method)
float hash3(float x, float y, float z) {
    return fract(sin(dot(vec3(x, y, z), vec3(12.9898, 78.233, 45.123))) * 43758.5453);
}

// Function to get the trail intensity (presence of a trail) from the map
int sense(float x, float y, float angle, float dst, int radius) {
	vec2 sensor;
	sensor.x = cos(angle) * dst;
	sensor.y = sin(angle) * dst;

	int sum = 0;
	for (int offsetX = -radius; offsetX <= radius; offsetX++) {
		for (int offsetY = -radius; offsetY <= radius; offsetY++) {
			int pos = int(x + sensor.x) + offsetX + (int(y + sensor.y) + offsetY) * int(push_constants.width);

			if (pos > 0 && pos < push_constants.width * push_constants.height - 1) {
				sum += int(read_buffer.data[pos] >> 24);
			}
		}
	}
	return sum;
}

float randomwandering(float x, float y, float angle) {
	float randomvalue = hash3(x, y, angle) * sin(hash3(x, y, angle) * 2) * 5 - 2.5;
	return randomvalue;
}

void main() {
	uint index = gl_GlobalInvocationID.x;
	if (index >= push_constants.agent_count) return;

	uint base_idx = index * 4;
	float x = agent_buffer.data[base_idx + 0];
	float y = agent_buffer.data[base_idx + 1];
	float angle = agent_buffer.data[base_idx + 2];
	float desiredangle = agent_buffer.data[base_idx + 3];
	float pi = 3.14159265359;

	float sensorDistance = 7.0;
	int sensorRadius = 3;
	float deg45 = pi / 4;

	int leftweight = sense(x, y, angle - deg45, sensorDistance, sensorRadius);
	int middleweight = sense(x, y, angle, sensorDistance, sensorRadius);
	int rightweight = sense(x, y, angle + deg45, sensorDistance, sensorRadius);

	if (leftweight > middleweight && leftweight > rightweight) {
		desiredangle -= (angle - (desiredangle - deg45)) * 0.2;
	}else if (rightweight > middleweight && rightweight > leftweight) {
		desiredangle -= (angle - (desiredangle + deg45)) * 0.2;
	}else {
		desiredangle -= (angle - desiredangle) * 0.2;
	}

	angle += (desiredangle - angle) * 0.7;

	// Compute movement
	float dx = cos(angle) * push_constants.speed;
	float dy = sin(angle) * push_constants.speed;
	x += dx;
	y += dy;


	// Boundary handling with randomized bounce angle
	if (x < 0) {
		angle += pi + (hash3(x, y, angle) - 0.5) * pi;
		x = 1;
	}
	if (x > push_constants.width) {
		angle += pi + (hash3(x, y, angle) - 0.5) * pi;
		x = push_constants.width - 1;
	}
	if (y < 0) {
		angle += pi + (hash3(x, y, angle) - 0.5) * pi;
		y = 1;
	}
	if (y > push_constants.height) {
		angle += pi + (hash3(x, y, angle) - 0.5) * pi;
		y = push_constants.height - 1;
	}

	// Store updated values
	agent_buffer.data[base_idx + 0] = x;
	agent_buffer.data[base_idx + 1] = y;
	agent_buffer.data[base_idx + 2] = angle;
	agent_buffer.data[base_idx + 3] = desiredangle;

	uint write_index = min(uint(x) + uint(y) * push_constants.width, push_constants.width * push_constants.height - 1);


	write_buffer.data[write_index] = 0xFFFFFFFF;
	
}
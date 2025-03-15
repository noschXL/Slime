#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// Storage buffer for agent data
layout(set = 0, binding = 0, std430) buffer AgentBuffer {
	float data[]; // Each agent has (x, y, angle)
} agent_buffer;

layout(set = 0, binding = 1, std430) buffer MapBuffer {
	uint map_data[]; // Map data (used for trail detection)
} map_buffer;

layout(push_constant) uniform PushConstants {
	float speed;
	uint agent_count;
	uint width;
	uint height;
} push_constants;

// Function to generate random float from a seed (simple hash-based method)
float hash3(float x, float y, float z) {
    return fract(sin(dot(vec3(x, y, z), vec3(12.9898, 78.233, 45.164))) * 43758.5453);
}

// Function to get the trail intensity (presence of a trail) from the map
bool is_trail(uint index) {
	return map_buffer.map_data[index] >> 24 > 0;
}

// Function to simulate turning towards the target
void turnTowards(vec2 currentPos, inout float angle, vec2 targetPos) {
	vec2 directionToTarget = normalize(targetPos - currentPos);
	float targetAngle = atan(directionToTarget.y, directionToTarget.x);
	float turnAmount = (targetAngle - angle);
	
	// Normalize the turn to [-pi, pi]
	if (turnAmount > 3.14159265359) {
		turnAmount -= 6.28318530718;
	} else if (turnAmount < -3.14159265359) {
		turnAmount += 6.28318530718;
	}
	
	// Turn 1/10 of the way toward the target
	angle += turnAmount * 0.1;  // Adjust this based on your speed
}

float randomwandering(float x, float y, float angle) {
	float randomvalue = hash3(x, y, angle) * sin(hash3(x, y, angle) * 2) * 0.2 - 0.1;
	return randomvalue;
}

void main() {
	uint index = gl_GlobalInvocationID.x;
	if (index >= push_constants.agent_count) return;

	uint base_idx = index * 3;
	float x = agent_buffer.data[base_idx + 0];
	float y = agent_buffer.data[base_idx + 1];
	float angle = agent_buffer.data[base_idx + 2];

	// Sensor checks for trail detection (left, center, right)
	float sensorDistance = 5.0;  // Distance in front of the agent to check
	bool leftTrail = is_trail(uint(x - sensorDistance) + push_constants.width * uint(y));
	bool centerTrail = is_trail(uint(x) + push_constants.width * uint(y + sensorDistance));  // Move along Y axis
	bool rightTrail = is_trail(uint(x + sensorDistance) + push_constants.width * uint(y));

	// If trail detected on the left, steer left
	if (leftTrail) {
		angle -= 0.01;
	}
	// If trail detected in the center, move forward
	else if (centerTrail) {
		// Do nothing for now (move straight)
	}
	// If trail detected on the right, steer right
	else if (rightTrail) {
		angle += 0.01;
	}
	angle += randomwandering(x, y, angle); 

	// Compute movement
	float dx = cos(angle) * push_constants.speed;
	float dy = sin(angle) * push_constants.speed;
	x += dx;
	y += dy;


	// Boundary handling with randomized bounce angle
	if (x < 0) {
		angle += 3.14159265359 + (hash3(x, y, angle) - 0.5) * 3.14159265359;
		x = 1;
	}
	if (x > push_constants.width) {
		angle += 3.14159265359 + (hash3(x, y, angle) - 0.5) * 3.14159265359;
		x = push_constants.width - 1;
	}
	if (y < 0) {
		angle += 3.14159265359 + (hash3(x, y, angle) - 0.5) * 3.14159265359;
		y = 1;
	}
	if (y > push_constants.height) {
		angle += 3.14159265359 + (hash3(x, y, angle) - 0.5) * 3.14159265359;
		y = push_constants.height - 1;
	}

	// Store updated values
	agent_buffer.data[base_idx + 0] = x;
	agent_buffer.data[base_idx + 1] = y;
	agent_buffer.data[base_idx + 2] = angle;
}

extends Node2D

@export var speed = 2
@export var steeringStrenght := 0.7

@export var followDesire := 0.2
@export var maxRandomRadiant := TAU #if > TAU

@export var AgentCount = 1000

@export var sensorDst = 7
@export var sensorRadius = 3

@export var StartCircleDiameter = 20

var blur_shader_file := load("res://blur.glsl")
var rd = RenderingServer.create_local_rendering_device()
var blur_shader_spirv
var blur_shader

var compute_shader_file = load("res://agents.glsl")
var compute_shader_spirv
var compute_shader

var image_buffers: Array[RID]
var agent_buffer: RID
var read_index := 0
var write_index := 1

var size
var map: PackedByteArray
var agents: Array
var screen_size = Vector2(1920, 1080)
var texture : ImageTexture

func ToIndex(vec: Vector2) -> int:
	return int(floor(vec.y)) * size.x + int(floor(vec.x))

func _ready():
	blur_shader_spirv = blur_shader_file.get_spirv()
	blur_shader = rd.shader_create_from_spirv(blur_shader_spirv)
	compute_shader_spirv = compute_shader_file.get_spirv()
	compute_shader = rd.shader_create_from_spirv(compute_shader_spirv)
	size = get_viewport().size
	map = PackedByteArray()  # Initialize the map array
	agents = []  # Initialize the agents array

	# Initialize map with RGBA values
	for i in range(size.x * size.y):
		map.append(255)  # R
		map.append(255)  # G
		map.append(255)  # B
		map.append(0)    # A

	# Generate agents starting positions
	for i in range(AgentCount):
		var pos: Vector2 = Vector2(size.x / 2, size.y / 2)
		var angle: float = randf_range(0, TAU)
		var desiredangle = -angle
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * randf_range(1, StartCircleDiameter)
		pos += offset
		agents.append([pos, -angle, desiredangle])
		
	image_buffers = [
		rd.storage_buffer_create(map.size(), map),
		rd.storage_buffer_create(map.size(), map)	
	]
	agent_buffer = rd.storage_buffer_create(agents.size() * 4 * 4, agents_to_packed_array())

	texture = ImageTexture.new()
	update_texture()

func encode_float(value: float) -> PackedByteArray:
	var data = PackedByteArray()
	data.resize(4)
	data.encode_float(0, value)
	return data

func encode_int(value: int) -> PackedByteArray:
	var data = PackedByteArray()
	data.resize(4)
	data.encode_s32(0, value)
	return data


func agents_to_packed_array() -> PackedByteArray:
	var data = PackedByteArray()
	for agent in agents:
		data.append_array(encode_float(agent[0].x))
		data.append_array(encode_float(agent[0].y))
		data.append_array(encode_float(agent[1]))
		data.append_array(encode_float(agent[2]))
	return data

func Update():
	UpdateAgents()
	UpdateBlur()
	read_index = read_index ^ 1
	write_index = write_index ^ 1

func UpdateAgents():
	# Create uniform
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(agent_buffer)

	var map_uniform := RDUniform.new()
	map_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	map_uniform.binding = 2  # Binding index for map buffer
	map_uniform.add_id(image_buffers[read_index])  # Assign the map buffer
	
	var blur_uniform := RDUniform.new()
	blur_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	blur_uniform.binding = 1  # Binding index for map buffer
	blur_uniform.add_id(image_buffers[write_index])  # Assign the map buffer

	var uniform_set := rd.uniform_set_create([uniform, map_uniform, blur_uniform], compute_shader, 0)

	# Push constants
	var push_constants = PackedByteArray()
	push_constants.append_array(encode_float(speed))
	push_constants.append_array(encode_float(steeringStrenght))
	
	push_constants.append_array(encode_float(followDesire))
	push_constants.append_array(encode_float(maxRandomRadiant))
	
	push_constants.append_array(encode_int(AgentCount))
	
	push_constants.append_array(encode_int(sensorDst))
	push_constants.append_array(encode_int(sensorRadius))
	
	push_constants.append_array(encode_int(size.x))
	push_constants.append_array(encode_int(size.y))

	push_constants.resize(48)

	# Execute compute shader
	var pipeline := rd.compute_pipeline_create(compute_shader)
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, 48)  # 4 floats (4 bytes each)
	rd.compute_list_dispatch(compute_list, AgentCount / 256. + 1, 1, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

func UpdateBlur():
	# Create uniform and bind it to the compute shader
	var read_uniform := RDUniform.new()
	read_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	read_uniform.binding = 0 # Matches the binding in shader
	read_uniform.add_id(image_buffers[read_index])
	
	var write_uniform := RDUniform.new()
	write_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	write_uniform.binding = 1 # Matches the binding in shader
	write_uniform.add_id(image_buffers[write_index])
	var uniform_set := rd.uniform_set_create([read_uniform, write_uniform], blur_shader, 0)
	
	# Compute pipeline
	var pipeline := rd.compute_pipeline_create(blur_shader)
	
	# Dispatch compute job
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	# **Set Push Constants (width, height + padding)**
	var push_constants = PackedByteArray()
	push_constants.resize(16) # Allocate 16 bytes
	push_constants.encode_u32(0, size.x) # Width
	push_constants.encode_u32(4, size.y) # Height
	# 8 bytes of padding (Vulkan requires push constants to be aligned to 16 bytes)

	rd.compute_list_set_push_constant(compute_list, push_constants, 16)  # Pass full 16 bytes

	# We calculate the number of dispatches needed for the image size
	var work_group_size = 16  # This should match your shader local_size
	var x_groups = int(ceil(size.x / float(work_group_size)))
	var y_groups = int(ceil(size.y / float(work_group_size)))
	
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	
	rd.compute_list_end()
	
	# Submit to GPU and wait for sync
	rd.submit()
	rd.sync()
	

# Function to update the texture with the current map
func update_texture() -> void:
	map = rd.buffer_get_data(image_buffers[write_index])
	var img = Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, map)
	texture = ImageTexture.create_from_image(img)  # Update the ImageTexture with the new map
	$Sprite2D.texture = texture  # Update the Sprite's texture

func _process(_delta: float) -> void:
	Update()  # Update agents' positions and map
	update_texture()  # Update the texture with the new map data
	

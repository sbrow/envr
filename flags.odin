package main

import "base:runtime"
import "core:reflect"
import "core:strings"

get_subtag :: proc(tag: string, id: string) -> (value: string, ok: bool) {
	parts := strings.split(tag, ",", context.temp_allocator)
	for part in parts {
		trimmed := strings.trim_space(part)
		if strings.has_prefix(trimmed, id) && len(trimmed) > len(id) && trimmed[len(id)] == '=' {
			return trimmed[len(id) + 1:], true
		}
		if trimmed == id {
			return "", true
		}
	}
	return "", false
}

is_bool_type :: proc(field: reflect.Struct_Field) -> bool {
	base_ti := runtime.type_info_base(field.type)
	_, is_bool := base_ti.variant.(runtime.Type_Info_Boolean)
	return is_bool
}

set_field :: proc(model: rawptr, field: reflect.Struct_Field, value: string) -> bool {
	ptr := rawptr(uintptr(model) + field.offset)
	base_ti := runtime.type_info_base(field.type)

	if _, is_bool := base_ti.variant.(runtime.Type_Info_Boolean); is_bool {
		(cast(^bool)ptr)^ = true
		return true
	}

	if _, is_string := base_ti.variant.(runtime.Type_Info_String); is_string {
		(cast(^string)ptr)^ = value
		return true
	}

	if enum_ti, is_enum := base_ti.variant.(runtime.Type_Info_Enum); is_enum {
		for name, i in enum_ti.names {
			if strings.equal_fold(value, name) {
				v := enum_ti.values[i]
				switch base_ti.size {
				case 1: (cast(^u8)ptr)^  = cast(u8)v
				case 2: (cast(^u16)ptr)^ = cast(u16)v
				case 4: (cast(^u32)ptr)^ = cast(u32)v
				case 8: (cast(^u64)ptr)^ = cast(u64)v
				}
				return true
			}
		}
	}

	return false
}

parse_flags :: proc(model: ^$T, args: []string) -> (overflow: []string) {
	field_count := reflect.struct_field_count(T)
	long_map := make(map[string]reflect.Struct_Field, field_count, context.temp_allocator)
	short_map := make(map[string]reflect.Struct_Field, field_count, context.temp_allocator)

	for i in 0..<field_count {
		field := reflect.struct_field_at(T, i)

		name, _ := strings.replace(field.name, "_", "-", -1, context.temp_allocator)
		args_tag := reflect.struct_tag_get(field.tag, "args")
		if n, ok := get_subtag(args_tag, "name"); ok {
			name = n
		}
		long_map[name] = field

		if s, ok := get_subtag(args_tag, "short"); ok {
			short_map[s] = field
		}
	}

	overflow_dyn := make([dynamic]string, 0, len(args), context.temp_allocator)

	i := 0
	for i < len(args) {
		arg := args[i]

		if strings.starts_with(arg, "--") {
			key := arg[2:]
			value := ""
			has_value := false

			if eq_idx := strings.index(key, "="); eq_idx >= 0 {
				value = key[eq_idx + 1:]
				key = key[:eq_idx]
				has_value = true
			}

			if field, ok := long_map[key]; ok {
				if is_bool_type(field) {
					set_field(model, field, "")
					i += 1
				} else if has_value {
					set_field(model, field, value)
					i += 1
				} else if i + 1 < len(args) && !strings.starts_with(args[i + 1], "-") {
					set_field(model, field, args[i + 1])
					i += 2
				} else {
					i += 1
				}
			} else {
				i += 1
			}
		} else if strings.starts_with(arg, "-") && len(arg) == 2 {
			short := arg[1:2]
			if field, ok := short_map[short]; ok {
				if is_bool_type(field) {
					set_field(model, field, "")
					i += 1
				} else if i + 1 < len(args) && !strings.starts_with(args[i + 1], "-") {
					set_field(model, field, args[i + 1])
					i += 2
				} else {
					i += 1
				}
			} else {
				i += 1
			}
		} else {
			append(&overflow_dyn, arg)
			i += 1
		}
	}

	return overflow_dyn[:]
}

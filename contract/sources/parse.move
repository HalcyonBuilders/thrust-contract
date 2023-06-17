module thrust::parse {
    use std::ascii;
    use std::string::{Self, String, utf8};
    use std::type_name;
    use std::vector;

    use sui::address;
    use sui:: hex;
    use sui::object::{Self, ID};

    // error constants
    const EINVALID_TYPE_NAME: u64 = 0;
    const ESUPPLIED_TYPE_CANNOT_BE_ABSTRACT: u64 = 1;
    const EINVALID_SLICE: u64 = 2;

    public fun empty(): String {
        string::utf8(vector::empty())
    }

    // Takes a slice of a vector from the start-index up to, but not including, the end-index.
    // Does not modify the original vector
    public fun slice<T: store + copy>(vec: &vector<T>, start: u64, end: u64): vector<T> {
        assert!(end >= start, EINVALID_SLICE);

        let (i, slice) = (start, vector::empty<T>());
        while (i < end) {
            vector::push_back(&mut slice, *vector::borrow(vec, i));
            i = i + 1;
        };

        slice
    }

    public fun type_name<T>(): String {
        utf8(ascii::into_bytes(type_name::into_string(type_name::get<T>())))
    }

    public fun type_name_decomposed<T>(): (ID, String, String, vector<String>) {
        decompose_type_name(type_name<T>())
    }

    public fun decompose_type_name(s1: String): (ID, String, String, vector<String>) {
        let delimiter = utf8(b"::");
        let len = address::length();

        if ((string::length(&s1) > len * 2 + 2) && (string::sub_string(&s1, len * 2, len * 2 + 2) == delimiter)) {
            // This is a fully qualified type, like <package-id>::<module-name>::<struct-name>

            let s2 = string::sub_string(&s1, len * 2 + 2, string::length(&s1));
            let j = string::index_of(&s2, &delimiter);
            assert!(string::length(&s2) > j, EINVALID_TYPE_NAME);

            let package_id_str = string::sub_string(&s1, 0, len * 2);
            let module_name = string::sub_string(&s2, 0, j);
            let struct_name_and_generics = string::sub_string(&s2, j + 2, string::length(&s2));

            let package_id = object::id_from_bytes(hex::decode(*string::bytes(&package_id_str)));
            let (struct_name, generics) = decompose_struct_name(struct_name_and_generics);

            (package_id, module_name, struct_name, generics)
        } else {
            // This is a primitive type, like vector<u64>
            let (struct_name, generics) = decompose_struct_name(s1);
            
            (object::id_from_address(@0x0), empty(), struct_name, generics)
        }
    }

    // Takes a struct-name like `MyStruct<T, G>` and returns (MyStruct, [T, G])
    public fun decompose_struct_name(s1: String): (String, vector<String>) {
        let (struct_name, generics_string) = parse_angle_bracket(s1);
        let generics = parse_comma_delimited_list(generics_string);
        (struct_name, generics)
    }

    // Faster than decomposing the entire type name
    public fun package_id<T>(): ID {
        let bytes_full = ascii::into_bytes(type_name::into_string(type_name::get<T>()));
        // hex doubles the number of characters used
        let bytes = slice(&bytes_full, 0, address::length() * 2); 
        object::id_from_bytes(hex::decode(bytes))
    }

    // Faster than decomposing the entire type name
    public fun module_name<T>(): String {
        let s1 = type_name<T>();
        let s2 = string::sub_string(&s1, address::length() * 2 + 2, string::length(&s1));
        let j = string::index_of(&s2, &utf8(b"::"));
        assert!(string::length(&s2) > j, EINVALID_TYPE_NAME);

        string::sub_string(&s2, 0, j)
    }

    // Returns <package_id>::<module_name>
    public fun package_id_and_module_name<T>(): String {
        let s1 = type_name<T>();
        package_id_and_module_name_(s1)
    }

    // More efficient than doing the package_id and module_name calls separately
    public fun package_id_and_module_name_(s1: String): String {
        let delimiter = utf8(b"::");
        let s2 = string::sub_string(&s1, (address::length() * 2) + 2, string::length(&s1));
        let j = string::index_of(&s2, &delimiter);

        assert!(string::length(&s2) > j, EINVALID_TYPE_NAME);

        let i = (address::length() * 2) + 2 + j;
        string::sub_string(&s1, 0, i)
    }

    // Returns the module_name + struct_name, without any generics, such as `my_module::CoolStruct`
    public fun module_and_struct_name<T>(): String {
        let (_, module_name, struct_name, _) = type_name_decomposed<T>();
        string::append(&mut module_name, utf8(b"::"));
        string::append(&mut module_name, struct_name);

        module_name
    }

    // Takes the module address of Type `T`, and appends an arbitrary string to the end of it
    // This creates a fully-qualified address for a struct that may not exist
    public fun append_struct_name<Type>(struct_name: String): String {
        append_struct_name_(package_id_and_module_name<Type>(), struct_name)
    }

    // Contains no input-validation that `module_addr` is actually a valid module address
    public fun append_struct_name_(module_addr: String, struct_name: String): String {
        string::append(&mut module_addr, utf8(b"::"));
        string::append(&mut module_addr, struct_name);

        module_addr
    }

    // ========== Parser Functions ==========

    // Takes something like `Option<u64>` and returns `u64`. Returns an empty-string if the string supplied 
    // does not contain `Option<`
    public fun parse_option(str: String): String {
        let len = string::length(&str);
        let i = string::index_of(&str, &utf8(b"Option"));

        if (i == len) empty()
        else {
            let (_, t) = parse_angle_bracket(string::sub_string(&str, i + 6, len));
            t
        }
    }

    // Example output:
    // "Option<vector<u64>>" -> ("Option", "vector<u64>")
    // "Coin<0x599::paul_coin::PaulCoin>" -> ("Coin", "0x599::paul_coin::PaulCoin")
    // NFT<ABC, XYZ> -> ("NFT", "ABC, XYZ")
    public fun parse_angle_bracket(str: String): (String, String) {
        let bytes = *string::bytes(&str);
        let (opening_bracket, closing_bracket) = (60u8, 62u8);
        let len = vector::length(&bytes);
        let (start, i, count) = (len, 0, 0);

        while (i < len) {
                let byte = *vector::borrow(&bytes, i);

                if (byte == opening_bracket) {
                    if (count == 0) start = i; // we found the first opening bracket
                    count = count + 1;
                } else if (byte == closing_bracket) {
                    if (count == 0 || count == 1) break; // we found the last closing bracket
                    count = count - 1;
                };

                i = i + 1;
            };

        if (i == len || (start + 1) >= i) (str, empty())
        else (string::sub_string(&str, 0, start), string::sub_string(&str, start + 1, i))
    }

    public fun parse_comma_delimited_list(str: String): vector<String> {
        let bytes = *string::bytes(&str);
        let (space, comma) = (32u8, 44u8);
        let result = vector::empty<String>();
        let (i, j, len) = (0, 0, string::length(&str));

        while (i < len) {
            let byte = *vector::borrow(&bytes, i);

            if (byte == comma) {
                let s = string::sub_string(&str, j, i);
                vector::push_back(&mut result, s);

                // We skip over single-spaces after commas
                if (i < len - 1) {
                    if (*vector::borrow(&bytes, i + 1) == space) {
                        j = i + 2;
                    } else {
                        j = i + 1;
                    };
                } else j = i + 1;
            } else if (i == len - 1) { // We've reached the end of the string
                let s = string::sub_string(&str, j, len);
                vector::push_back(&mut result, s);
            };

            i = i + 1;
        };

        // We didn't find any commas, so we just return the original string
        if (vector::length(&result) == 0) result = vector[str];

        result
    }

    // =============== Validation ===============

    // Returns true for types with generics like `Coin<T>`, returns false for all others
    public fun has_generics<T>(): bool {
        let str = type_name<T>();
        let i = string::index_of(&str, &utf8(b"<"));

        if (i == string::length(&str)) false
        else true
    }

    // Returns true for strings like 'vector<u8>', returns false for all others
    public fun is_vector(str: String): bool {
        if (string::length(&str) < 6) false
        else {
            if (string::sub_string(&str, 0, 6) == utf8(b"vector")) true
            else false
        }
    }

    // =============== Module Comparison ===============

    public fun is_same_module<Type1, Type2>(): bool {
        let module1 = package_id_and_module_name<Type1>();
        let module2 = package_id_and_module_name<Type2>();

        (module1 == module2)
    }

}
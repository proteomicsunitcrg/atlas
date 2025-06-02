#!/bin/bash

# Function to insert a key-value pair into the file
insert_key_value() {
    local key="$1"
    local value="$2"
    local file="$3"
    
    # Append new key-value pair to the file
    echo "$key=$value" >> "$file"
}

# Function to modify the value of an existing key
modify_key_value() {
    local key="$1"
    local new_value="$2"
    local file="$3"
    
    # Use sed to find and replace the value of the key
    sed -i "s/^$key=.*/$key=$new_value/" "$file"
}

# Function to remove a key-value pair from the file
remove_key_value() {
    local key="$1"
    local file="$2"
    
    # Use sed to remove the line containing the key
    sed -i "/^$key=/d" "$file"
}

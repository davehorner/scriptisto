#!/usr/bin/env scriptisto

// scriptisto-begin
// script_src: src/main.rs
// build_cmd: cargo build --release && strip ./target/release/script
// target_bin: ./target/release/script
// files:
//  - path: Cargo.toml
//    content: |
//     [package]
//     name = "script"
//     version = "0.1.0"
//     edition = "2021"
// 
//     [dependencies]
//     clap = { version = "4", features = ["derive"] }
// scriptisto-end

use clap::{Parser, Subcommand};
use std::fs;
use std::path::Path;
use std::process::{Command, Stdio};

#[derive(Debug, Parser)]
#[command(name = "script", about = "Manage and test scriptisto-generated scripts.")]
struct Opt {
    #[command(subcommand)]
    command: CommandOption,
}

#[derive(Debug, Subcommand)]
enum CommandOption {
    /// Generate scripts if the `scripts` directory does not exist
    Generate,
    /// Test all scripts in the `scripts` directory
    TestAll,
}

fn main() {
    let opt = Opt::parse();

    match opt.command {
        CommandOption::Generate => generate_scripts(),
        CommandOption::TestAll => test_all_scripts(),
    }
}

fn generate_scripts() {
    let scripts_dir = Path::new("scripts");
    if scripts_dir.exists() {
        println!("The 'scripts' directory already exists. Skipping generation.");
        return;
    }

    // Create the `scripts` folder
    fs::create_dir(scripts_dir).expect("Failed to create 'scripts' directory");

    // Fetch the template list using `scriptisto new`
    let output = Command::new("scriptisto")
        .arg("new")
        .output()
        .expect("Failed to execute 'scriptisto new'");

    let output_str = String::from_utf8_lossy(&output.stdout);

    // Parse the output to extract template names and extensions
    let mut templates = Vec::new();
    for line in output_str.lines() {
        if line.starts_with("| ") {
            let parts: Vec<&str> = line.split('|').map(|s| s.trim()).collect();
            if parts.len() > 2 && parts[0] != "+" {
                let template = parts[1];
                let extension = parts[3].trim_start_matches('.'); // Remove leading dot
                templates.push((template.to_string(), extension.to_string()));
            }
        }
    }

    // Generate scripts
    for (template, extension) in templates {
        println!("Generating script for template: {}", template);

        // Execute the `scriptisto new` command
        let output = Command::new("scriptisto")
            .arg("new")
            .arg(&template)
            .output()
            .expect("Failed to execute 'scriptisto new <template>'");

        if output.status.success() {
            // Save the script to the `scripts` folder
            let filename = format!("scripts/{}.{}", template, extension);
            fs::write(&filename, output.stdout)
                .unwrap_or_else(|_| panic!("Failed to write script for template: {}", template));

            // Make the script executable
            let chmod_status = Command::new("chmod")
                .arg("+x")
                .arg(&filename)
                .status()
                .expect("Failed to change file permissions");

            if chmod_status.success() {
                println!("Generated: {}", filename);
            } else {
                eprintln!("Failed to make the script executable: {}", filename);
            }
        } else {
            eprintln!("Failed to generate script for template: {}", template);
        }
    }
}

fn test_all_scripts() {
    let scripts_dir = Path::new("scripts");
    if !scripts_dir.exists() {
        eprintln!("The 'scripts' directory does not exist. Please run the 'generate' command first.");
        return;
    }

    // Change the current working directory to the `scripts` folder
    std::env::set_current_dir(scripts_dir).expect("Failed to change directory to 'scripts'");

    let mut success_count = 0;
    let mut failure_count = 0;

    // Iterate over all scripts in the current directory
    for entry in fs::read_dir(".").expect("Failed to read 'scripts' directory") {
        let entry = entry.expect("Failed to access a script file");
        let path = entry.path();
        if path.is_file() {
            let script_name = path.file_name().unwrap().to_string_lossy();
            let success_output_file = format!("{}.output.txt", script_name);
            let failure_output_file = format!("{}.fail.txt", script_name);

            println!("Testing script: {}", script_name);

            // Run the script and capture output
            let output = Command::new(&path)
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .output()
                .expect(&format!("Failed to execute script: {}", script_name));

            if output.status.success() {
                success_count += 1;

                // Write successful output to the corresponding file
                fs::write(&success_output_file, &output.stdout)
                    .unwrap_or_else(|_| panic!("Failed to write output for script: {}", script_name));
                println!("Success: Output saved to {}", success_output_file);
            } else {
                failure_count += 1;

                // Write failure output to the corresponding file
                fs::write(&failure_output_file, &output.stderr)
                    .unwrap_or_else(|_| panic!("Failed to write failure output for script: {}", script_name));
                eprintln!("Failure: Output saved to {}", failure_output_file);
            }
        }
    }

    let total_tests = success_count + failure_count;
    let success_percentage = (success_count as f64 / total_tests as f64) * 100.0;

    // Print summary statistics
    println!("\nTest Results:");
    println!("Total scripts tested: {}", total_tests);
    println!("Successful scripts: {}", success_count);
    println!("Failed scripts: {}", failure_count);
    println!("Success rate: {:.2}%", success_percentage);
}


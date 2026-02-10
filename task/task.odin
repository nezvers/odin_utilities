package task

import "core:fmt"
import "core:strings"
import os2 "core:os/os2"
import "core:log"


exec :: proc(cmd: []string) -> (code: int, error: os2.Error) {
	process := os2.process_start({ command = cmd, stdin = os2.stdin, stdout = os2.stdout, stderr = os2.stderr }) or_return
	state := os2.process_wait(process) or_return
	os2.process_close(process) or_return
	return state.exit_code, nil
}

// Use curl and wget as fallback.
// Both are available on Linux, Windows, Mac
download_file :: proc(url:string, destination_file_path:string)->(ok:bool){
	log.infof("\nDownloading: \n\turl:{0} \n\tpath{1}\n", url, destination_file_path)
	// cmd:string = fmt.aprintf("curl -fsSL \"{0}\", -o \"{1}\"", url, destination_file_path)
	cmd: []string = { "curl", "-fsSL", url, "-o", destination_file_path }

	code, err := exec(cmd)
	if (err == nil && code == 0) {
		ok = true
		return
	}

	if err != nil {
		log.errorf("Curl: {}", err)
	}
	if code != 0 {
		log.errorf("Curl exited with non-zero code {}", code)
	}

	// Fallback to wget
	cmd = { "wget", "-q", url, "-O", destination_file_path }
	code, err = exec(cmd)
	if (err == nil && code == 0) {
		ok = true
		return
	}

	if err != nil {
		log.errorf("Wget: {}", err)
	}
	if code != 0 {
		log.errorf("Wget exited with non-zero code {}", code)
	}
	return
}

extract_tar_archive :: proc(archive_path:string, target_dir:string, strip_lvl:string = "0")->(ok:bool){
	log.infof("\nExtract TAR: \n\tarchive:{0} \n\tdirectory:{1} \n\tstrip:{2}\n", archive_path, target_dir, strip_lvl)
	strip: [128]u8
	fmt.bprintf(strip[:], "--strip-components={0}", strip_lvl)
	builder := strings.builder_from_bytes(strip[:])
	strip_str:string = strings.to_string(builder)
	cmd: []string = { "tar", "-xzf", archive_path, "-C", target_dir, strip_str }
	
	code, err: = exec(cmd)
	if (err == nil && code == 0) {
		ok = true
		return
	}

	if err != nil {
		log.errorf("TAR: {}", err)
	}
	if code != 0 {
		log.errorf("TAR exited with non-zero code {}", code)
	}
	return
}

extract_zip_archive :: proc(archive_path:string, target_dir:string, strip_lvl:string = "0")->(ok:bool){
	log.infof("\nExtract ZIP: \n\tarchive:{0} \n\tdirectory:{1} \n\tstrip:{2}\n", archive_path, target_dir, strip_lvl)
	strip: [128]u8
	fmt.bprintf(strip[:], "--strip-components={0}", strip_lvl)
	builder := strings.builder_from_bytes(strip[:])
	strip_str:string = strings.to_string(builder)
	cmd: []string = { "tar", "-xf", archive_path, "-C", target_dir, strip_str }
	
	code, err: = exec(cmd)
	if (err == nil && code == 0) {
		ok = true
		return
	}

	if err != nil {
		log.errorf("ZIP: {}", err)
	}
	if code != 0 {
		log.errorf("ZIP exited with non-zero code {}", code)
	}
	return
}

// Clones a repository in current working directory
// tag is also a branch name
git_clone :: proc(git_repo:string, tag:string, recursive:bool = false, single_branch:bool = true, depth:string = "1")->(ok:bool){
	log.infof("\nGit cloning: \n\trepository:{0} \n\ttag:{1} \n\tstrip:{2}\n", git_repo, tag)
	cmd: [9]string
	cmd[0] = "git"
	cmd[1] = "clone"
	count:u32 = 2
	if recursive {
		cmd[count] = "--recursive"
		count +=1 
	}
	if single_branch {
		cmd[count] = "--single-branch"
		count +=1
	}
	if tag != "" {
		cmd[count] = "--branch"
		cmd[count +1] = tag
		count += 2
	}
	if depth != "" {
		cmd[count] = "--depth"
		cmd[count +1] = depth
		count += 2
	}
	cmd[count] = git_repo
	count +=1

	code, err: = exec(cmd[:count])
	if (err == nil && code == 0) {
		ok = true
		return
	}

	if err != nil {
		log.errorf("GIT: {}", err)
	}
	if code != 0 {
		log.errorf("GIT exited with non-zero code {}", code)
	}
	return
}
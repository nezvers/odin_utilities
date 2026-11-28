// The JavaScript side of file_browser/io_web.odin: the file chooser of the browser and downloads.
//
//   <script src="file_browser.js"></script>          before odin.js
//   imports = { ...imports, ...fileBrowserJsImports }
//   setFileBrowserWasmMemory(exports.memory)          once the wasm memory exists
//
// The program polls (`pick_poll`), nothing calls into it. A chooser can only be opened by a person's click: the program asks for it in the frame after the click, which the browsers allow
// for a few seconds after the gesture.

let fileBrowserMemory = null;

function setFileBrowserWasmMemory(memory) {
	fileBrowserMemory = memory;
}

const fileBrowserPick = {
	status: 0,          // 0 pending, 1 ready, 2 cancelled, 3 failed
	name: "",
	bytes: null,
	input: null,
};

function fileBrowserBytes(pointer, length) {
	// the memory can grow between calls: take the buffer again every time
	return new Uint8Array(fileBrowserMemory.buffer, pointer, length);
}

function fileBrowserString(pointer, length) {
	return new TextDecoder("utf-8").decode(fileBrowserBytes(pointer, length));
}

function fileBrowserMime(name) {
	const dot = name.lastIndexOf(".");
	const extension = dot >= 0 ? name.slice(dot + 1).toLowerCase() : "";
	const types = {
		png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", bmp: "image/bmp", gif: "image/gif", qoi: "image/qoi", tga: "image/x-tga",
		wav: "audio/wav", ogg: "audio/ogg", mp3: "audio/mpeg", flac: "audio/flac",
		txt: "text/plain", json: "application/json",
	};
	return types[extension] || "application/octet-stream";
}

const fileBrowserJsImports = {
	file_browser: {
		file_browser_pick_start: function (acceptPointer, acceptLength) {
			const accept = fileBrowserString(acceptPointer, acceptLength);
			fileBrowserPick.status = 0;
			fileBrowserPick.bytes = null;
			fileBrowserPick.name = "";
			if (fileBrowserPick.input) {
				fileBrowserPick.input.remove();
			}
			const input = document.createElement("input");
			input.type = "file";
			if (accept.length > 0) {
				input.accept = accept;
			}
			input.style.display = "none";
			input.addEventListener("change", () => {
				const file = input.files && input.files[0];
				if (!file) {
					fileBrowserPick.status = 2;
					return;
				}
				file.arrayBuffer().then((buffer) => {
					fileBrowserPick.name = file.name;
					fileBrowserPick.bytes = new Uint8Array(buffer);
					fileBrowserPick.status = 1;
				}).catch((error) => {
					console.error("file_browser: could not read the file", error);
					fileBrowserPick.status = 3;
				});
			});
			input.addEventListener("cancel", () => {
				fileBrowserPick.status = 2;
			});
			document.body.appendChild(input);
			fileBrowserPick.input = input;
			input.click();
		},

		file_browser_pick_poll: function () {
			return fileBrowserPick.status;
		},

		file_browser_pick_name: function (pointer, length) {
			const encoded = new TextEncoder().encode(fileBrowserPick.name);
			const count = Math.min(encoded.length, length);
			fileBrowserBytes(pointer, count).set(encoded.subarray(0, count));
			return count;
		},

		// -1: the file is bigger than the buffer of the program; it stays for a try with a bigger one
		file_browser_pick_take: function (pointer, length) {
			const bytes = fileBrowserPick.bytes;
			if (bytes === null) {
				return 0;
			}
			if (bytes.length > length) {
				return -1;
			}
			fileBrowserBytes(pointer, bytes.length).set(bytes);
			fileBrowserPick.bytes = null;
			fileBrowserPick.status = 0;
			return bytes.length;
		},

		file_browser_download: function (namePointer, nameLength, dataPointer, dataLength) {
			const name = fileBrowserString(namePointer, nameLength);
			// a copy: the memory of the program changes after this call
			const copy = fileBrowserBytes(dataPointer, dataLength).slice();
			const url = URL.createObjectURL(new Blob([copy], { type: fileBrowserMime(name) }));
			const link = document.createElement("a");
			link.href = url;
			link.download = name;
			link.style.display = "none";
			document.body.appendChild(link);
			link.click();
			link.remove();
			setTimeout(() => URL.revokeObjectURL(url), 10000);
		},
	},
};

// SPDX-License-Identifier: GPL-3.0-or-later
.pragma library

// What Files shows about a file besides its name (M0.4): its kind for the
// type icon, whether it gets a thumbnail, and sizes in decimal units.

const archives = ["application/zip", "application/x-tar", "application/x-compressed-tar",
                  "application/gzip", "application/x-gzip", "application/x-bzip2",
                  "application/x-bzip2-compressed-tar", "application/x-xz",
                  "application/x-xz-compressed-tar", "application/zstd",
                  "application/x-zstd-compressed-tar", "application/x-7z-compressed",
                  "application/vnd.rar", "application/x-rar", "application/x-cd-image",
                  "application/x-iso9660-image"];
const documents = ["application/pdf", "application/epub+zip", "application/rtf",
                   "application/msword", "application/vnd.ms-excel",
                   "application/vnd.ms-powerpoint"];
const texts = ["application/json", "application/xml", "application/x-shellscript",
               "application/javascript", "application/x-desktop", "application/toml",
               "application/x-yaml"];
const documentPrefixes = ["application/vnd.oasis.opendocument.",
                          "application/vnd.openxmlformats-officedocument."];

// "folder", "image", "audio", "video", "text", "document", "archive" or
// "other".
function kindOf(mimeType, isDir) {
    const mime = String(mimeType || "");
    if (isDir) {
        return "folder";
    }
    for (const kind of ["image", "audio", "video"]) {
        if (mime.startsWith(kind + "/")) {
            return kind;
        }
    }
    if (archives.indexOf(mime) >= 0) {
        return "archive";
    }
    if (documents.indexOf(mime) >= 0 || documentPrefixes.some(prefix => mime.startsWith(prefix))) {
        return "document";
    }
    if (mime.startsWith("text/") || texts.indexOf(mime) >= 0) {
        return "text";
    }
    return "other";
}

// Thumbnails only for local files in common raster formats under 20 MB, so a
// large or unusual file never stalls the folder view.
const thumbnailTypes = ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp"];
const thumbnailLimit = 20 * 1000 * 1000;

function canThumbnail(mimeType, size, url) {
    const bytes = Number(size);
    return thumbnailTypes.indexOf(String(mimeType)) >= 0 && bytes > 0 && bytes < thumbnailLimit
        && String(url).startsWith("file:");
}

// Decimal units, as disks are sold: "9.8 GB", "16 GB", "512 MB".
function formatBytes(bytes) {
    const units = ["B", "kB", "MB", "GB", "TB"];
    let v = Math.max(0, Number(bytes) || 0);
    let i = 0;
    while (v >= 1000 && i < units.length - 1) {
        v /= 1000;
        i += 1;
    }
    const digits = i === 0 || v >= 100 ? 0 : 1;
    return v.toFixed(digits).replace(/\.0$/, "") + " " + units[i];
}

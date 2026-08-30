// Client-side driver for LiveView's `external:` upload contract: posts each
// entry straight to the presigned Tigris/S3 form URL (spec §11), reporting
// progress back to the entry so the upload UI reflects real progress.
const Uploaders = {}

Uploaders.S3 = function (entries, onViewError) {
  entries.forEach(entry => {
    const {url, fields} = entry.meta
    const formData = new FormData()
    Object.entries(fields).forEach(([key, val]) => formData.append(key, val))
    formData.append("file", entry.file)

    const xhr = new XMLHttpRequest()
    onViewError(() => xhr.abort())

    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        entry.progress(100)
      } else {
        entry.error()
      }
    }
    xhr.onerror = () => entry.error()

    xhr.upload.addEventListener("progress", event => {
      if (event.lengthComputable) {
        const percent = Math.round((event.loaded / event.total) * 100)
        if (percent < 100) entry.progress(percent)
      }
    })

    xhr.open("POST", url, true)
    xhr.send(formData)
  })
}

export default Uploaders

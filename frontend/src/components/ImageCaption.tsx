import { useCallback, useRef, useState } from "react";

const API_BASE = import.meta.env.VITE_API_URL ?? "";

interface PredictResponse {
  caption: string;
  strategy: string;
  beam_width: number;
  filename: string;
}

export default function ImageCaption() {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [caption, setCaption] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleFile = useCallback((f: File) => {
    setFile(f);
    setPreview(URL.createObjectURL(f));
    setCaption(null);
    setError(null);
  }, []);

  const onDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setDragOver(false);
      const f = e.dataTransfer.files[0];
      if (f?.type.startsWith("image/")) handleFile(f);
    },
    [handleFile],
  );

  const onInputChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const f = e.target.files?.[0];
      if (f) handleFile(f);
    },
    [handleFile],
  );

  const reset = useCallback(() => {
    setFile(null);
    setPreview(null);
    setCaption(null);
    setError(null);
    if (inputRef.current) inputRef.current.value = "";
  }, []);

  const predict = useCallback(async () => {
    if (!file) return;
    setLoading(true);
    setError(null);
    setCaption(null);

    try {
      const form = new FormData();
      form.append("file", file);

      const res = await fetch(`${API_BASE}/predict?strategy=beam&beam_width=3`, {
        method: "POST",
        body: form,
      });

      if (!res.ok) {
        const body = await res.json().catch(() => null);
        throw new Error(body?.detail ?? `Server error (${res.status})`);
      }

      const data: PredictResponse = await res.json();
      setCaption(data.caption);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setLoading(false);
    }
  }, [file]);

  return (
    <>
      {!preview && (
        <div
          className={`upload-zone${dragOver ? " drag-over" : ""}`}
          onDragOver={(e) => {
            e.preventDefault();
            setDragOver(true);
          }}
          onDragLeave={() => setDragOver(false)}
          onDrop={onDrop}
          onClick={() => inputRef.current?.click()}
        >
          <p>
            Drag &amp; drop an image here, or <span className="browse">browse</span>
          </p>
          <input
            ref={inputRef}
            type="file"
            accept="image/*"
            hidden
            onChange={onInputChange}
          />
        </div>
      )}

      {preview && (
        <div className="preview-section">
          <img src={preview} alt="Preview" />
          <div className="preview-actions">
            <button className="btn btn-primary" onClick={predict} disabled={loading}>
              {loading && <span className="spinner" />}
              {loading ? "Generating..." : "Generate Caption"}
            </button>
            <button className="btn btn-secondary" onClick={reset} disabled={loading}>
              Clear
            </button>
          </div>
        </div>
      )}

      {error && <div className="error-banner">{error}</div>}

      {caption && (
        <div className="result-card">
          <h3>Generated Caption</h3>
          <p className="caption-text">{caption}</p>
        </div>
      )}
    </>
  );
}

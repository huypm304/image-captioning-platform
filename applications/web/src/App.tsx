import ImageCaption from "./components/ImageCaption";

export default function App() {
  return (
    <div className="app">
      <header className="app-header">
        <h1>AI Image Caption</h1>
        <p>Upload an image and get an AI-generated caption</p>
      </header>
      <main>
        <ImageCaption />
      </main>
    </div>
  );
}

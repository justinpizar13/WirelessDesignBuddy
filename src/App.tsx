import React, { useRef, useState, useEffect } from "react";
import * as pdfjsLib from "pdfjs-dist";

pdfjsLib.GlobalWorkerOptions.workerSrc = `https://cdnjs.cloudflare.com/ajax/libs/pdf.js/${pdfjsLib.version}/pdf.worker.min.js`;

const WALL_TYPES = {
  drywall: { color: "#F4E2D8", loss: 3 },
  glass: { color: "#ADD8E6", loss: 2 },
  concrete: { color: "#A9A9A9", loss: 10 },
  metal: { color: "#800080", loss: 15 },
};

type WallType = keyof typeof WALL_TYPES;

interface Wall {
  x: number;
  y: number;
  x2: number;
  y2: number;
  type: WallType;
}

interface AccessPoint {
  x: number;
  y: number;
}

type Mode = "edit" | "draw-wall" | "place-ap";

function App() {
  const [imageSrc, setImageSrc] = useState<string | null>(null);
  const [scale, setScale] = useState(1);
  const [translate, setTranslate] = useState({ x: 0, y: 0 });
  const [isDragging, setIsDragging] = useState(false);
  const [walls, setWalls] = useState<Wall[]>([]);
  const [drawingWall, setDrawingWall] = useState<{ x: number; y: number } | null>(null);
  const [wallType, setWallType] = useState<WallType>("drywall");
  const [accessPoints, setAccessPoints] = useState<AccessPoint[]>([]);
  const [mode, setMode] = useState<Mode>("edit");

  const [selectedAPIndex, setSelectedAPIndex] = useState<number | null>(null);
  const [selectedWallIndex, setSelectedWallIndex] = useState<number | null>(null);

  const dragStart = useRef({ x: 0, y: 0 });
  const fileInputRef = useRef<HTMLInputElement>(null);

   useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Backspace" || e.key === "Delete") {
        if (selectedAPIndex !== null) {
          setAccessPoints((prev) => prev.filter((_, i) => i !== selectedAPIndex));
          setSelectedAPIndex(null);
        } else if (selectedWallIndex !== null) {
          setWalls((prev) => prev.filter((_, i) => i !== selectedWallIndex));
          setSelectedWallIndex(null);
        }
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [selectedAPIndex, selectedWallIndex]);

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const url = URL.createObjectURL(file);

    if (file.type === "application/pdf") {
      const loadingTask = pdfjsLib.getDocument(url);
      const pdf = await loadingTask.promise;
      const page = await pdf.getPage(1);
      const viewport = page.getViewport({ scale: 2 });

      const canvas = document.createElement("canvas");
      const context = canvas.getContext("2d")!;
      canvas.width = viewport.width;
      canvas.height = viewport.height;

      await page.render({ canvasContext: context, viewport }).promise;

      setImageSrc(canvas.toDataURL("image/png"));
    } else if (file.type.startsWith("image/")) {
      setImageSrc(url);
    }
  };

  const handleWheel = (e: React.WheelEvent) => {
    e.preventDefault();
    const delta = -e.deltaY / 500;
    setScale((prev) => Math.max(0.1, prev + delta));
  };

  const handleMouseDown = (e: React.MouseEvent) => {
    const svg = e.currentTarget as SVGSVGElement;
    const pt = svg.createSVGPoint();
    pt.x = e.clientX;
    pt.y = e.clientY;
    const cursorpt = pt.matrixTransform(svg.getScreenCTM()!.inverse());

    if (mode === "draw-wall") {
      if (!drawingWall) {
        setDrawingWall({ x: cursorpt.x, y: cursorpt.y });
      }
    } else if (mode === "place-ap") {
      setAccessPoints((prev) => [...prev, { x: cursorpt.x, y: cursorpt.y }]);
    } else {
      setIsDragging(true);
      dragStart.current = { x: e.clientX - translate.x, y: e.clientY - translate.y };
    }
  };

  const handleMouseMove = (e: React.MouseEvent) => {
    if (isDragging) {
      setTranslate({
        x: e.clientX - dragStart.current.x,
        y: e.clientY - dragStart.current.y,
      });
    }
    else if (mode === "edit" && selectedAPIndex !== null && e.buttons === 1) {
  const svg = e.currentTarget as SVGSVGElement;
  const pt = svg.createSVGPoint();
  pt.x = e.clientX;
  pt.y = e.clientY;
  const cursorpt = pt.matrixTransform(svg.getScreenCTM()!.inverse());

  setAccessPoints((prev) =>
    prev.map((ap, idx) =>
      idx === selectedAPIndex ? { ...ap, x: cursorpt.x, y: cursorpt.y } : ap
    )
  );
}
  };

  const handleMouseUp = (e: React.MouseEvent) => {
    setIsDragging(false);
    if (mode === "draw-wall" && drawingWall) {
      const svg = e.currentTarget as SVGSVGElement;
      const pt = svg.createSVGPoint();
      pt.x = e.clientX;
      pt.y = e.clientY;
      const cursorpt = pt.matrixTransform(svg.getScreenCTM()!.inverse());

      setWalls((prev) => [...prev, { ...drawingWall, x2: cursorpt.x, y2: cursorpt.y, type: wallType }]);
      setDrawingWall(null);
    }
  };

  const renderWalls = () => {
    return walls.map((wall, idx) => (
      <line
        key={idx}
        x1={wall.x}
        y1={wall.y}
        x2={wall.x2}
        y2={wall.y2}
        stroke={WALL_TYPES[wall.type].color}
        strokeWidth={selectedWallIndex === idx ? 6 : 4}
        onClick={(e) => {
          if (mode === "edit") {
            e.stopPropagation();
            setSelectedWallIndex(idx);
            setSelectedAPIndex(null);
          }
        }}
      />
    ));
  };

  const renderAccessPoints = () => {
    return accessPoints.map((ap, idx) => (
      <circle
  key={idx}
  cx={ap.x}
  cy={ap.y}
  r={selectedAPIndex === idx ? 12 : 10}
  fill="#1E90FF"
  stroke="#000"
  strokeWidth={1}
  onClick={(e) => {
    if (mode === "edit") {
      e.stopPropagation();
      setSelectedAPIndex(idx);
      setSelectedWallIndex(null);
    }
  }}
/>
    ));
  };

  return (
    <div className="h-screen flex overflow-hidden">
      {/* Sidebar */}
      <div className="w-64 bg-white border-r border-gray-300 p-4 space-y-4">
        <h2 className="text-xl font-semibold mb-4">Toolbox</h2>
        <button
          className="w-full px-3 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
          onClick={() => fileInputRef.current?.click()}
        >
          Upload Floorplan
        </button>
        <input
          type="file"
          ref={fileInputRef}
          className="hidden"
          accept="image/*,application/pdf"
          onChange={handleFileChange}
        />

        <div>
          <label className="block text-sm font-medium mb-1">Mode</label>
          <select
            className="w-full border rounded p-1"
            value={mode}
            onChange={(e) => setMode(e.target.value as Mode)}
          >
            <option value="edit">Edit</option>
            <option value="draw-wall">Draw Wall</option>
            <option value="place-ap">Place Access Point</option>
          </select>
        </div>

        {mode === "draw-wall" && (
          <div>
            <label className="block text-sm font-medium mb-1">Wall Type</label>
            <select
              className="w-full border rounded p-1"
              value={wallType}
              onChange={(e) => setWallType(e.target.value as WallType)}
            >
              {Object.keys(WALL_TYPES).map((key) => (
                <option key={key} value={key}>{key}</option>
              ))}
            </select>
          </div>
        )}
      </div>

      {/* Canvas Area */}
      <div
        className="flex-1 bg-gray-200 relative overflow-hidden"
        onWheel={handleWheel}
      >
        <svg
          className="w-[4000px] h-[3000px] cursor-crosshair"
          onMouseDown={handleMouseDown}
          onMouseMove={handleMouseMove}
          onMouseUp={handleMouseUp}
          style={{ transform: `translate(${translate.x}px, ${translate.y}px) scale(${scale})`, transformOrigin: "0 0" }}
        >
          {imageSrc && <image href={imageSrc} x={0} y={0} width={3000} height={2000} />}
          {renderWalls()}
          {renderAccessPoints()}
          {drawingWall && mode === "draw-wall" && (
            <line
              x1={drawingWall.x}
              y1={drawingWall.y}
              x2={drawingWall.x}
              y2={drawingWall.y}
              stroke={WALL_TYPES[wallType].color}
              strokeWidth={4}
            />
          )}
        </svg>
      </div>
    </div>
  );
}

export default App;
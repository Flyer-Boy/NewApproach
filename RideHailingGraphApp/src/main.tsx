import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import Provider from "./provider/index.tsx";
import "./styles/index.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Provider />
  </StrictMode>,
);

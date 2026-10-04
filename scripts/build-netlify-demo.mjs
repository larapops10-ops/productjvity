import { cp, mkdir, writeFile } from "node:fs/promises";

const destination = new URL("../dist/netlify-demo/", import.meta.url);
await mkdir(destination, { recursive: true });
await cp(new URL("../apps/web/", import.meta.url), destination, { recursive: true });
await writeFile(new URL("demo-config.js", destination), "window.PRODUCTJVITY_DEMO = true;\n", "utf8");
console.log("Netlify demo built in dist/netlify-demo");

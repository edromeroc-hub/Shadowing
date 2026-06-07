import type { IncomingMessage, ServerResponse } from "http";
import { createRequire } from "module";

const apiRequire = createRequire(import.meta.url);
const { createApp } = apiRequire("../dist/server.cjs");

const appPromise = createApp({ includeFrontend: false });

export default async function handler(req: IncomingMessage, res: ServerResponse) {
  const app = await appPromise;
  return app(req, res);
}

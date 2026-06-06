# Deploying Aura apps

`aura deploy <file.aura>` generates the assets for the target you choose. Which
target fits depends on whether your app uses **Torch**.

| App type | Uses Torch? | Recommended host | `aura deploy` |
| --- | --- | --- | --- |
| `neural_network` / `transfer` models, `train`, `evaluate` | **Yes** (LibTorch) | Container host: Fly.io, Render, Railway, Cloud Run (GPU via Modal / Replicate / Cloud Run GPU) | default → `Dockerfile` |
| `from openai` / `from ollama` (LLM proxy), text/greeting | **No** | Vercel (Ruby serverless), or any container host | `--target vercel` → `vercel.json` + `api/index.rb` |

## Why not Vercel for Torch models?

Vercel runs **serverless functions**, not long-lived servers: the function
bundle is capped (hundreds of MB), there's no GPU, execution times out quickly,
and there is no persistent process. A Torch model server loads LibTorch (GB
scale) and stays resident — it cannot fit those limits. Use a **container host**
for Torch apps.

## Container hosts (Torch and everything else)

```bash
aura deploy app.aura          # writes app.rb, Dockerfile, .dockerignore
docker build -t app .
docker run -p 3000:3000 app
```

Deploy that image to Fly.io, Render, Railway, or Cloud Run. For GPU
training/inference, push to a GPU platform (Modal, Replicate, RunPod, or Cloud
Run with GPUs).

> The generated `Dockerfile` installs the web stack (`sinatra puma json`). To
> actually run Torch models in the container you must also install `torch-rb`
> and the LibTorch system libraries in the image.

## Vercel (LLM-only apps)

For an LLM-proxy or text app (no Torch):

```bash
aura deploy chatbot.aura --target vercel   # writes chatbot.rb, api/index.rb, vercel.json
vercel deploy
```

`api/index.rb` exposes the Sinatra app as a Rack `Handler` for Vercel's Ruby
runtime. Set secrets (e.g. `OPENAI_API_KEY`, `AURA_API_TOKEN`) in the Vercel
dashboard; the generated app reads them from the environment (and loads a local
`.env` via dotenv in development).

> Vercel's Ruby runtime is community-maintained. The generated `vercel.json`
> uses the `@vercel/ruby` builder — confirm/adjust it for your account if Vercel
> changes the runtime identifier. If you'd rather not depend on it, the
> container path above also works for LLM apps.

If you ask Vercel to host a Torch app, `aura deploy --target vercel` refuses with
a message pointing you back to the container path.

## Databases (optional): Vercel Storage → Supabase / Neon

Aura's core framework is **database-free** — the only state it persists is model
weights (`save weights to "..."` → a `.pth` file). You don't need a database to
build, train, or serve models.

When you *do* want persistence (logging predictions, storing metrics, or real
user accounts behind `authenticate with`), provision Postgres from **Vercel's
Storage tab** (which integrates Supabase and Neon) and expose it to the app as an
environment variable:

- Set `DATABASE_URL` (and any provider keys) as Vercel env vars, or in a local
  `.env`. The generated app already loads the environment via dotenv, so reading
  `ENV["DATABASE_URL"]` from your own code/route needs no extra wiring.
- **Supabase** additionally provides hosted Auth, which is a natural backend for
  the `authenticate with :token` directive if you outgrow the simple bearer-token
  check.
- **Neon** is plain serverless Postgres (scales to zero) — a good fit for
  low-traffic prediction/metric logging.

These integrations live in *your* application code today; a first-class Aura
persistence primitive is on the roadmap, not in the framework yet.

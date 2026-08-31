function formatGoodNewsWindow(start, end) {
  const opts = { month: "short", day: "numeric", year: "numeric" };
  const fmt = (value) => {
    if (!value) return "";
    const parsed = new Date(`${value}T00:00:00`);
    if (Number.isNaN(parsed.getTime())) return value;
    return parsed.toLocaleDateString("en-US", opts);
  };
  const from = fmt(start);
  const to = fmt(end);
  if (from && to) return `${from} – ${to}`;
  return "";
}

function goodNewsSourceHost(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch (err) {
    return url;
  }
}

function renderGoodNews(data) {
  const meta = document.getElementById("good-news-meta");
  const lede = document.getElementById("good-news-lede");
  const list = document.getElementById("good-news-items");
  if (!meta || !lede || !list || !data || !Array.isArray(data.items)) return;

  const range = formatGoodNewsWindow(data.window_start, data.window_end);
  const updated = data.updated ? `Updated ${data.updated.slice(0, 10)}` : "";
  meta.textContent = [range, updated].filter(Boolean).join(" · ");
  lede.textContent = data.lede || "";
  lede.hidden = !data.lede;

  list.innerHTML = "";
  data.items.forEach((item) => {
    const article = document.createElement("article");
    article.className = "good-news-item";

    const heading = document.createElement("h4");
    heading.textContent = item.headline || "";
    article.appendChild(heading);

    const summary = document.createElement("p");
    summary.textContent = item.summary || "";
    article.appendChild(summary);

    if (item.source_url) {
      const source = document.createElement("a");
      source.href = item.source_url;
      source.rel = "noopener noreferrer";
      const label = item.source_title || goodNewsSourceHost(item.source_url);
      source.textContent = item.date ? `${label} · ${item.date}` : label;
      article.appendChild(source);
    }

    list.appendChild(article);
  });
}

function loadGoodNews() {
  const fallback = "./good-news.fallback.json";
  fetch("/good-news.json", { cache: "no-store" })
    .then((response) => (response.ok ? response.json() : Promise.reject()))
    .catch(() => fetch(fallback).then((response) => {
      if (!response.ok) throw new Error("good news unavailable");
      return response.json();
    }))
    .then(renderGoodNews)
    .catch(() => {
      const meta = document.getElementById("good-news-meta");
      if (meta) meta.textContent = "Digest unavailable";
    });
}

document.addEventListener("DOMContentLoaded", loadGoodNews);

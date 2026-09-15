import { chmodSync, writeFileSync } from "fs";

export function csvCell(value: unknown): string {
  let text: string;
  if (value === null || value === undefined) text = "";
  else if (Array.isArray(value) || typeof value === "object") {
    text = JSON.stringify(value);
  } else {
    text = String(value);
  }
  return /[;"\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export function csvContent(
  columns: readonly string[],
  rows: ReadonlyArray<Record<string, unknown>>
): string {
  const lines = [columns.map(csvCell).join(";")];
  for (const row of rows) {
    lines.push(columns.map((column) => csvCell(row[column])).join(";"));
  }
  return `\uFEFF${lines.join("\r\n")}\r\n`;
}

export function writePrivateCsv(
  path: string,
  columns: readonly string[],
  rows: ReadonlyArray<Record<string, unknown>>
): void {
  writeFileSync(path, csvContent(columns, rows), { encoding: "utf8", mode: 0o600 });
  chmodSync(path, 0o600);
}


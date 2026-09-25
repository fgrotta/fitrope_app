// Fake Firestore in memoria per i test WhatsApp (functions/src/whatsapp/).
//
// Supporta quello che usano registro invii, conferma, cron e callable di prova:
// `collection().doc()` con create/get/update, e query con `where` (==, >=, <=,
// array-contains-any), `limit` e `get`. Le scritture si applicano allo `store`
// passato, senza copiarlo: un test di ripresa passa lo stesso store a un secondo
// fake e vede lo stato lasciato dal primo run.
//
// `whereCalls` registra i filtri, per asserire che le query non richiedono indici
// compositi; `ops` registra le operazioni sui documenti (`create users/u1`, ...).

export type Data = Record<string, unknown>;
/** collection → docId → dati. */
export type Store = Record<string, Record<string, Data>>;

export interface WhereCall {
  collection: string;
  field: string;
  op: string;
  value: unknown;
}

export interface WhatsappFakeDbOptions {
  /** Errore da lanciare su `create` del documento indicato (`collection/id`). */
  createError?: (key: string) => Error | undefined;
  /** Errore da lanciare su `update` del documento indicato (`collection/id`). */
  updateError?: (key: string) => Error | undefined;
}

function comparable(value: unknown): unknown {
  const maybe = value as { toMillis?: () => number } | null;
  if (maybe && typeof maybe.toMillis === "function") return maybe.toMillis();
  return value;
}

function codedError(message: string, code: number): Error {
  const err = new Error(message) as Error & { code?: number };
  err.code = code;
  return err;
}

export function makeWhatsappDb(store: Store = {}, opts: WhatsappFakeDbOptions = {}) {
  const whereCalls: WhereCall[] = [];
  const ops: string[] = [];

  const coll = (name: string): Record<string, Data> => {
    if (!store[name]) store[name] = {};
    return store[name];
  };

  const snapshotOf = (name: string, id: string) => {
    const data = coll(name)[id];
    return {
      id,
      exists: data !== undefined,
      data: () => (data === undefined ? undefined : { ...data }),
    };
  };

  interface Filter {
    field: string;
    op: string;
    value: unknown;
  }

  const matches = (data: Data, { field, op, value }: Filter): boolean => {
    const actual = data[field];
    switch (op) {
      case "==":
        return comparable(actual) === comparable(value);
      case ">=":
        return actual !== undefined && (comparable(actual) as number) >= (comparable(value) as number);
      case "<=":
        return actual !== undefined && (comparable(actual) as number) <= (comparable(value) as number);
      case "array-contains-any":
        if ((value as unknown[]).length > 30) {
          throw new Error("array-contains-any accetta al massimo 30 valori");
        }
        return Array.isArray(actual) && actual.some((v) => (value as unknown[]).includes(v));
      default:
        throw new Error(`Operatore non supportato dal fake: ${op}`);
    }
  };

  const query = (name: string, filters: Filter[], max: number | null): Record<string, unknown> => ({
    where: (field: string, op: string, value: unknown) => {
      whereCalls.push({ collection: name, field, op, value });
      return query(name, [...filters, { field, op, value }], max);
    },
    limit: (n: number) => query(name, filters, n),
    get: async () => {
      let ids = Object.keys(coll(name)).filter((id) =>
        filters.every((f) => matches(coll(name)[id], f))
      );
      if (max !== null) ids = ids.slice(0, max);
      const docs = ids.map((id) => snapshotOf(name, id));
      return { docs, empty: docs.length === 0, size: docs.length };
    },
    doc: (id: string) => {
      const key = `${name}/${id}`;
      return {
        id,
        create: async (data: Data) => {
          ops.push(`create ${key}`);
          const injected = opts.createError?.(key);
          if (injected) throw injected;
          if (coll(name)[id] !== undefined) {
            throw codedError(`6 ALREADY_EXISTS: Document already exists: ${key}`, 6);
          }
          coll(name)[id] = { ...data };
        },
        get: async () => {
          ops.push(`get ${key}`);
          return snapshotOf(name, id);
        },
        update: async (patch: Data) => {
          ops.push(`update ${key}`);
          const injected = opts.updateError?.(key);
          if (injected) throw injected;
          if (coll(name)[id] === undefined) {
            throw codedError(`5 NOT_FOUND: No document to update: ${key}`, 5);
          }
          coll(name)[id] = { ...coll(name)[id], ...patch };
        },
      };
    },
  });

  const db = { collection: (name: string) => query(name, [], null) };

  // `as never`: il fake copre solo la parte di Firestore che usano i moduli WhatsApp.
  return { db: db as never, store, whereCalls, ops };
}

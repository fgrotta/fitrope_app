// Fake Firestore in-memory per i test degli handler enrollment/admin.
// Supporta: query corsi per uid e range startDate, doc utenti, query utenti
// array-contains (courses/waitlistCourses), query subscriptions per userId,
// transazioni con update/delete che APPLICANO le scritture allo store (così i
// test asseriscono lo stato finale). NB: esegue la closure di transazione una
// sola volta (niente retry/contention: quella semantica è coperta dai test di
// integrazione su emulatore, categoria C).

export type Data = Record<string, unknown>;

export interface FakeStore {
  users: Record<string, Data>;
  courses: Record<string, Data>; // docId -> data (campo uid dentro)
  subs: Record<string, Data>;
}

interface Filter {
  f: string;
  op: string;
  v: unknown;
}

export function makeDb(store: FakeStore) {
  const userDocRef = (id: string) => ({
    _kind: "userDoc",
    _id: id,
    get: async () => ({
      exists: store.users[id] !== undefined,
      data: () => store.users[id],
    }),
  });

  const courseDocRef = (docId: string) => ({ _kind: "courseDoc", _id: docId });

  const runCoursesQuery = (filters: Filter[]) => {
    let entries = Object.entries(store.courses);
    for (const { f, op, v } of filters) {
      if (f === "uid" && op === "==") {
        entries = entries.filter(([, d]) => d.uid === v);
      } else if (f === "startDate") {
        const millis = (v as { toMillis: () => number }).toMillis();
        entries = entries.filter(([, d]) => {
          const start = (d.startDate as { toMillis: () => number }).toMillis();
          return op === ">=" ? start >= millis : start <= millis;
        });
      }
    }
    return {
      empty: entries.length === 0,
      docs: entries.map(([id, d]) => ({
        id,
        data: () => d,
        ref: courseDocRef(id),
      })),
    };
  };

  const runUsersQuery = (q: { _f: string; _v: unknown }) => {
    const docs = Object.entries(store.users)
      .filter(([, d]) => Array.isArray(d[q._f]) && (d[q._f] as unknown[]).includes(q._v))
      .map(([id, d]) => ({ id, data: () => d, ref: userDocRef(id) }));
    return { empty: docs.length === 0, docs };
  };

  const runSubsQuery = (q: { _userId: unknown }) => {
    const docs = Object.entries(store.subs)
      .filter(([, d]) => d.userId === q._userId)
      .map(([id, d]) => ({
        id,
        data: () => d,
        ref: { _kind: "subDoc", _id: id },
      }));
    return { docs };
  };

  const coursesQuery = (filters: Filter[]): Data => ({
    _kind: "coursesQuery",
    _filters: filters,
    where: (f: string, op: string, v: unknown) =>
      coursesQuery([...filters, { f, op, v }]),
    limit: () => coursesQuery(filters),
    get: async () => runCoursesQuery(filters),
  });

  const db = {
    collection(name: string) {
      if (name === "users") {
        return {
          doc: userDocRef,
          where: (f: string, op: string, v: unknown) => {
            if (op !== "array-contains") {
              throw new Error(`users.where op non gestito: ${op}`);
            }
            const q = { _kind: "usersQuery", _f: f, _v: v };
            return { ...q, get: async () => runUsersQuery(q) };
          },
        };
      }
      if (name === "courses") return coursesQuery([]);
      if (name === "subscriptions") {
        return {
          where: (_f: string, _op: string, v: unknown) => ({
            _kind: "subsQuery",
            _userId: v,
          }),
        };
      }
      throw new Error(`collezione non gestita: ${name}`);
    },
    runTransaction: async (fn: (tx: unknown) => Promise<void>) => {
      const tx = {
        get: async (q: {
          _kind: string;
          _filters?: Filter[];
          _id?: string;
          _userId?: string;
          _f?: string;
          _v?: unknown;
        }) => {
          if (q._kind === "coursesQuery") return runCoursesQuery(q._filters!);
          if (q._kind === "userDoc") {
            return {
              exists: store.users[q._id!] !== undefined,
              data: () => store.users[q._id!],
            };
          }
          if (q._kind === "usersQuery") {
            return runUsersQuery(q as { _f: string; _v: unknown });
          }
          if (q._kind === "subsQuery") return runSubsQuery(q as { _userId: unknown });
          throw new Error(`tx.get non gestito: ${q._kind}`);
        },
        update: (ref: { _kind: string; _id: string }, data: Data) => {
          const target = storeFor(ref._kind);
          Object.assign(target[ref._id], data);
        },
        delete: (ref: { _kind: string; _id: string }) => {
          delete storeFor(ref._kind)[ref._id];
        },
      };
      await fn(tx);
    },
  };

  function storeFor(kind: string): Record<string, Data> {
    return kind === "courseDoc"
      ? store.courses
      : kind === "userDoc"
        ? store.users
        : store.subs;
  }

  return db as never;
}

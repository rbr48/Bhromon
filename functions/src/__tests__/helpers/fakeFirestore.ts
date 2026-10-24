/**
 * Minimal in-memory Firestore for scaling tests: supports the query shapes
 * the scheduled jobs use (where <, ==, != ; limit), batches (enforcing the
 * 500-write limit), getAll, and counts every read.
 */
type Data = Record<string, any>;

export class FakeFirestore {
  collections = new Map<string, Map<string, Data>>();
  stats = { queryGets: 0, docGets: 0, getAllCalls: 0, batchCommits: 0, maxBatchWrites: 0, singleUpdates: 0 };

  seed(collection: string, id: string, data: Data) {
    if (!this.collections.has(collection)) this.collections.set(collection, new Map());
    this.collections.get(collection)!.set(id, { ...data });
  }

  docs(collection: string): Map<string, Data> {
    if (!this.collections.has(collection)) this.collections.set(collection, new Map());
    return this.collections.get(collection)!;
  }

  collection(name: string) {
    return new FakeQuery(this, name, [], undefined);
  }

  ref(collection: string, id: string) {
    const store = this;
    return {
      id,
      path: `${collection}/${id}`,
      _collection: collection,
      get: async () => {
        store.stats.docGets++;
        return store.snapshot(collection, id);
      },
      update: async (data: Data) => {
        const docs = store.docs(collection);
        docs.set(id, { ...docs.get(id), ...data });
        store.stats.singleUpdates++;
      },
    };
  }

  snapshot(collection: string, id: string) {
    const data = this.docs(collection).get(id);
    return {
      id,
      exists: data !== undefined,
      ref: this.ref(collection, id),
      data: () => (data ? { ...data } : undefined),
    };
  }

  async getAll(...refs: any[]) {
    this.stats.getAllCalls++;
    return refs.map((r) => this.snapshot(r._collection, r.id));
  }

  batch() {
    const store = this;
    const ops: Array<() => void> = [];
    return {
      update(ref: any, data: Data) {
        ops.push(() => {
          const docs = store.docs(ref._collection);
          docs.set(ref.id, { ...docs.get(ref.id), ...data });
        });
      },
      delete(ref: any) {
        ops.push(() => store.docs(ref._collection).delete(ref.id));
      },
      set(ref: any, data: Data) {
        ops.push(() => store.docs(ref._collection).set(ref.id, { ...data }));
      },
      async commit() {
        if (ops.length > 500) {
          throw new Error(`INVALID_ARGUMENT: maximum 500 writes allowed per request (got ${ops.length})`);
        }
        store.stats.batchCommits++;
        store.stats.maxBatchWrites = Math.max(store.stats.maxBatchWrites, ops.length);
        ops.forEach((op) => op());
      },
    };
  }
}

type Filter = { field: string; op: string; value: any };

const toComparable = (v: any) => (v instanceof Date ? v.getTime() : v?.toMillis ? v.toMillis() : v);

class FakeQuery {
  constructor(
    private store: FakeFirestore,
    private name: string,
    private filters: Filter[],
    private max: number | undefined,
    private byId = false,
    private afterId: string | undefined = undefined,
  ) {}

  /** Only document-id ordering is supported (the backfill's paging). */
  orderBy(_field: unknown) {
    return new FakeQuery(this.store, this.name, this.filters, this.max, true, this.afterId);
  }

  startAfter(id: string) {
    return new FakeQuery(this.store, this.name, this.filters, this.max, this.byId, id);
  }

  doc(id: string) {
    return this.store.ref(this.name, id);
  }

  where(field: string, op: string, value: any) {
    return new FakeQuery(this.store, this.name, [...this.filters, { field, op, value }], this.max, this.byId, this.afterId);
  }

  limit(n: number) {
    return new FakeQuery(this.store, this.name, this.filters, n, this.byId, this.afterId);
  }

  async get() {
    this.store.stats.queryGets++;
    let entries = [...this.store.docs(this.name).entries()];
    if (this.byId) entries.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
    if (this.afterId !== undefined) entries = entries.filter(([id]) => id > this.afterId!);
    const matches = entries.filter(([, data]) =>
      this.filters.every(({ field, op, value }) => {
        const actual = toComparable(data[field]);
        const expected = toComparable(value);
        switch (op) {
          case '==': return actual === expected;
          case '!=': return actual !== undefined && actual !== expected;
          case '<': return actual !== undefined && actual < expected;
          default: throw new Error(`unsupported op ${op}`);
        }
      }),
    );
    const page = this.max === undefined ? matches : matches.slice(0, this.max);
    const docs = page.map(([id]) => this.store.snapshot(this.name, id));
    return { docs, size: docs.length, empty: docs.length === 0 };
  }
}

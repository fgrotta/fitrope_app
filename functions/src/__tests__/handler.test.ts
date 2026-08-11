import {
  sendOneSignalNotificationHandler,
  ensureOneSignalUserHandler,
  ensureOneSignalEmailSubscription,
  removeOneSignalEmailHandler,
  ONESIGNAL_APP_ID,
  ONESIGNAL_API_URL,
  ONESIGNAL_USERS_URL,
  ONESIGNAL_SUBSCRIPTIONS_URL,
  ONESIGNAL_SUBSCRIPTIONS_BY_TOKEN_URL,
  HandlerRequest,
} from "../handler";
import { HttpsError } from "firebase-functions/v2/https";

// Silenzia i log durante i test
jest.mock("firebase-functions", () => ({
  logger: {
    info: jest.fn(),
    error: jest.fn(),
    warn: jest.fn(),
  },
}));

const API_KEY = "test-api-key";

// Dipendenze finte per l'handler di invio: db Firestore minimale (users/{uid})
// ed ensure mockata, senza inizializzare firebase-admin (stile fakeDbReturning
// di certificateEmails.test.ts).
function makeDeps(overrides?: {
  users?: Record<string, Record<string, unknown> | undefined>;
  ensure?: jest.Mock;
  getError?: Error;
}) {
  const ensure = overrides?.ensure ?? jest.fn().mockResolvedValue({});
  const requestedDocs: string[] = [];
  const db = {
    collection: () => ({
      doc: (id: string) => ({
        get: async () => {
          requestedDocs.push(id);
          if (overrides?.getError) {
            throw overrides.getError;
          }
          const data = overrides?.users?.[id];
          return { exists: data != null, data: () => data };
        },
      }),
    }),
  } as never;
  return { db, ensure, requestedDocs };
}

describe("sendOneSignalNotificationHandler", () => {
  let fetchMock: jest.Mock;

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  function mockOneSignalSuccess(data: Record<string, unknown> = { id: "notif-123" }) {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => data,
    } as Response);
  }

  function mockOneSignalError(status: number, errors: string[]) {
    fetchMock.mockResolvedValue({
      ok: false,
      status,
      json: async () => ({ errors }),
    } as Response);
  }

  describe("Autenticazione", () => {
    test("rifiuta richieste non autenticate", async () => {
      const request: HandlerRequest = {
        auth: null,
        data: { include_aliases: { external_id: ["u1"] } },
      };

      await expect(
        sendOneSignalNotificationHandler(request, API_KEY, makeDeps())
      ).rejects.toThrow(HttpsError);
      await expect(
        sendOneSignalNotificationHandler(request, API_KEY, makeDeps())
      ).rejects.toMatchObject({ code: "unauthenticated" });
      expect(fetchMock).not.toHaveBeenCalled();
    });

    test("accetta richieste autenticate", async () => {
      mockOneSignalSuccess();
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { include_aliases: { external_id: ["u1"] } },
      };

      const result = await sendOneSignalNotificationHandler(request, API_KEY, makeDeps());
      expect(result).toEqual({ id: "notif-123" });
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });
  });

  describe("Validazione payload", () => {
    test("rifiuta payload null", async () => {
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: null,
      };

      await expect(
        sendOneSignalNotificationHandler(request, API_KEY, makeDeps())
      ).rejects.toMatchObject({ code: "invalid-argument" });
      expect(fetchMock).not.toHaveBeenCalled();
    });

    test("rifiuta payload stringa", async () => {
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: "not-an-object",
      };

      await expect(
        sendOneSignalNotificationHandler(request, API_KEY, makeDeps())
      ).rejects.toMatchObject({ code: "invalid-argument" });
      expect(fetchMock).not.toHaveBeenCalled();
    });

    test("accetta payload oggetto vuoto", async () => {
      mockOneSignalSuccess();
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: {},
      };

      await sendOneSignalNotificationHandler(request, API_KEY, makeDeps());
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });
  });

  describe("Inoltro a OneSignal", () => {
    test("inietta app_id server-side anche se il client non lo fornisce", async () => {
      mockOneSignalSuccess();
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { include_aliases: { external_id: ["u1"] } },
      };

      await sendOneSignalNotificationHandler(request, API_KEY, makeDeps());

      const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
      expect(sentBody.app_id).toBe(ONESIGNAL_APP_ID);
    });

    test("sovrascrive app_id se il client tenta di inviarne uno diverso", async () => {
      mockOneSignalSuccess();
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { app_id: "malicious-app-id", include_aliases: { external_id: ["u1"] } },
      };

      await sendOneSignalNotificationHandler(request, API_KEY, makeDeps());

      const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
      expect(sentBody.app_id).toBe(ONESIGNAL_APP_ID);
    });

    test("usa l'API key fornita nell'header Authorization", async () => {
      mockOneSignalSuccess();
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { include_aliases: { external_id: ["u1"] } },
      };

      await sendOneSignalNotificationHandler(request, API_KEY, makeDeps());

      const headers = fetchMock.mock.calls[0][1].headers;
      expect(headers.Authorization).toBe(`Key ${API_KEY}`);
    });

    test("chiama il corretto endpoint OneSignal", async () => {
      mockOneSignalSuccess();
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { include_aliases: { external_id: ["u1"] } },
      };

      await sendOneSignalNotificationHandler(request, API_KEY, makeDeps());
      expect(fetchMock).toHaveBeenCalledWith(
        ONESIGNAL_API_URL,
        expect.objectContaining({ method: "POST" })
      );
    });

    test("inoltra tutti i campi del payload", async () => {
      mockOneSignalSuccess();
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: {
          include_aliases: { external_id: ["u1", "u2"] },
          target_channel: "email",
          email_subject: "Test",
          email_body: "<html>body</html>",
          send_after: "2026-05-01T19:00:00.000Z",
        },
      };

      await sendOneSignalNotificationHandler(request, API_KEY, makeDeps());

      const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
      expect(sentBody.include_aliases).toEqual({ external_id: ["u1", "u2"] });
      expect(sentBody.target_channel).toBe("email");
      expect(sentBody.email_subject).toBe("Test");
      expect(sentBody.email_body).toBe("<html>body</html>");
      expect(sentBody.send_after).toBe("2026-05-01T19:00:00.000Z");
    });
  });

  describe("Gestione risposte OneSignal", () => {
    test("ritorna il body della risposta in caso di successo", async () => {
      mockOneSignalSuccess({ id: "abc-123", recipients: 5 });
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { include_aliases: { external_id: ["u1"] } },
      };

      const result = await sendOneSignalNotificationHandler(request, API_KEY, makeDeps());
      expect(result).toEqual({ id: "abc-123", recipients: 5 });
    });

    test("lancia HttpsError internal quando OneSignal risponde con errore", async () => {
      mockOneSignalError(400, ["Invalid app_id"]);
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { include_aliases: { external_id: ["u1"] } },
      };

      await expect(
        sendOneSignalNotificationHandler(request, API_KEY, makeDeps())
      ).rejects.toMatchObject({
        code: "internal",
        message: expect.stringContaining("Invalid app_id"),
      });
    });

    test("gestisce risposta errore senza campo errors", async () => {
      fetchMock.mockResolvedValue({
        ok: false,
        status: 500,
        json: async () => ({}),
      } as Response);

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { include_aliases: { external_id: ["u1"] } },
      };

      await expect(
        sendOneSignalNotificationHandler(request, API_KEY, makeDeps())
      ).rejects.toMatchObject({
        code: "internal",
        message: "Errore OneSignal",
      });
    });

    test("lancia HttpsError unavailable se fetch fallisce", async () => {
      fetchMock.mockRejectedValue(new Error("Network error"));
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { include_aliases: { external_id: ["u1"] } },
      };

      await expect(
        sendOneSignalNotificationHandler(request, API_KEY, makeDeps())
      ).rejects.toMatchObject({
        code: "unavailable",
        message: "Impossibile contattare OneSignal",
      });
    });
  });

  describe("Ensure destinatari email", () => {
    const { logger } = jest.requireMock("firebase-functions");

    function emailRequest(externalIds: string[]): HandlerRequest {
      return {
        auth: { uid: "user-1" },
        data: {
          include_aliases: { external_id: externalIds },
          target_channel: "email",
          email_subject: "Oggetto",
          email_body: "<html>body</html>",
        },
      };
    }

    test("chiama ensure per ogni destinatario PRIMA della POST a OneSignal", async () => {
      const order: string[] = [];
      const ensure = jest.fn().mockImplementation(async () => {
        order.push("ensure");
      });
      fetchMock.mockImplementation(async () => {
        order.push("post");
        return { ok: true, status: 200, json: async () => ({ id: "n1" }) } as Response;
      });
      const deps = makeDeps({
        users: { u1: { email: "u1@x.it" }, u2: { email: "u2@x.it" } },
        ensure,
      });

      await sendOneSignalNotificationHandler(emailRequest(["u1", "u2"]), API_KEY, deps);

      expect(ensure).toHaveBeenCalledWith("u1", "u1@x.it", API_KEY);
      expect(ensure).toHaveBeenCalledWith("u2", "u2@x.it", API_KEY);
      expect(order).toEqual(["ensure", "ensure", "post"]);
    });

    test("legge l'email dal documento users/{uid}", async () => {
      mockOneSignalSuccess();
      const deps = makeDeps({ users: { u1: { email: "u1@x.it" } } });

      await sendOneSignalNotificationHandler(emailRequest(["u1"]), API_KEY, deps);

      expect(deps.requestedDocs).toEqual(["u1"]);
    });

    test("email non usabile ('-', vuota o assente): salta ensure ma invia comunque", async () => {
      mockOneSignalSuccess();
      const deps = makeDeps({ users: { u1: { email: "-" }, u2: { email: "" }, u3: {} } });

      await sendOneSignalNotificationHandler(emailRequest(["u1", "u2", "u3"]), API_KEY, deps);

      expect(deps.ensure).not.toHaveBeenCalled();
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(logger.warn).toHaveBeenCalledWith(
        expect.stringContaining("email non usabile"),
        expect.objectContaining({ externalId: "u1" })
      );
    });

    test("utente non trovato su Firestore: warn e invio procede", async () => {
      mockOneSignalSuccess();
      const deps = makeDeps();

      await sendOneSignalNotificationHandler(emailRequest(["sconosciuto"]), API_KEY, deps);

      expect(deps.ensure).not.toHaveBeenCalled();
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(logger.warn).toHaveBeenCalledWith(
        expect.stringContaining("utente non trovato"),
        expect.objectContaining({ externalId: "sconosciuto" })
      );
    });

    test("un ensure fallito non blocca gli altri destinatari né l'invio", async () => {
      mockOneSignalSuccess();
      const ensure = jest.fn().mockImplementation((id: string) =>
        id === "u1" ? Promise.reject(new Error("boom")) : Promise.resolve({})
      );
      const deps = makeDeps({
        users: { u1: { email: "u1@x.it" }, u2: { email: "u2@x.it" } },
        ensure,
      });

      await sendOneSignalNotificationHandler(emailRequest(["u1", "u2"]), API_KEY, deps);

      expect(ensure).toHaveBeenCalledTimes(2);
      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(logger.warn).toHaveBeenCalledWith(
        "Ensure destinatario fallito, invio comunque",
        expect.objectContaining({ externalId: "u1" })
      );
    });

    test("un errore del db non blocca l'invio", async () => {
      mockOneSignalSuccess();
      const deps = makeDeps({ getError: new Error("firestore down") });

      await sendOneSignalNotificationHandler(emailRequest(["u1"]), API_KEY, deps);

      expect(deps.ensure).not.toHaveBeenCalled();
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });

    test("canale push: non tocca né db né ensure", async () => {
      mockOneSignalSuccess();
      const deps = makeDeps({ users: { u1: { email: "u1@x.it" } } });
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: {
          include_aliases: { external_id: ["u1"] },
          target_channel: "push",
          contents: { it: "ciao" },
        },
      };

      await sendOneSignalNotificationHandler(request, API_KEY, deps);

      expect(deps.requestedDocs).toEqual([]);
      expect(deps.ensure).not.toHaveBeenCalled();
    });

    test("email senza include_aliases o con external_id vuoto: nessun ensure", async () => {
      mockOneSignalSuccess();
      const deps = makeDeps();

      await sendOneSignalNotificationHandler(
        { auth: { uid: "user-1" }, data: { target_channel: "email", email_subject: "x" } },
        API_KEY,
        deps
      );
      await sendOneSignalNotificationHandler(emailRequest([]), API_KEY, deps);

      expect(deps.ensure).not.toHaveBeenCalled();
      expect(deps.requestedDocs).toEqual([]);
    });

    test("deduplica gli external_id ripetuti", async () => {
      mockOneSignalSuccess();
      const deps = makeDeps({ users: { u1: { email: "u1@x.it" } } });

      await sendOneSignalNotificationHandler(emailRequest(["u1", "u1"]), API_KEY, deps);

      expect(deps.ensure).toHaveBeenCalledTimes(1);
    });
  });

  describe("Silent failure su 200", () => {
    const { logger } = jest.requireMock("firebase-functions");

    const request = (): HandlerRequest => ({
      auth: { uid: "user-1" },
      data: { include_aliases: { external_id: ["u1"] } },
    });

    test("logga warning su 200 con errors nel body", async () => {
      mockOneSignalSuccess({ id: "", errors: { invalid_aliases: { external_id: ["u1"] } } });

      await sendOneSignalNotificationHandler(request(), API_KEY, makeDeps());

      expect(logger.warn).toHaveBeenCalledWith(
        expect.stringContaining("errors nel body"),
        expect.anything()
      );
    });

    test("logga warning su 200 con recipients: 0", async () => {
      mockOneSignalSuccess({ id: "n1", recipients: 0 });

      await sendOneSignalNotificationHandler(request(), API_KEY, makeDeps());

      expect(logger.warn).toHaveBeenCalledWith(
        expect.stringContaining("recipients: 0"),
        expect.anything()
      );
    });

    test("nessun warning su 200 con recipients positivi", async () => {
      mockOneSignalSuccess({ id: "n1", recipients: 3 });

      await sendOneSignalNotificationHandler(request(), API_KEY, makeDeps());

      expect(logger.warn).not.toHaveBeenCalled();
    });
  });
});

describe("ensureOneSignalUserHandler", () => {
  let fetchMock: jest.Mock;

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  function mockFetchResponse(status: number, data: Record<string, unknown>) {
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => data,
    } as Response;
  }

  describe("Autenticazione e validazione", () => {
    test("rifiuta richieste non autenticate", async () => {
      const request: HandlerRequest = {
        auth: null,
        data: { externalId: "user-1", email: "test@example.com" },
      };

      await expect(
        ensureOneSignalUserHandler(request, API_KEY)
      ).rejects.toMatchObject({ code: "unauthenticated" });
      expect(fetchMock).not.toHaveBeenCalled();
    });

    test("rifiuta payload senza externalId", async () => {
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { email: "test@example.com" },
      };

      await expect(
        ensureOneSignalUserHandler(request, API_KEY)
      ).rejects.toMatchObject({ code: "invalid-argument" });
      expect(fetchMock).not.toHaveBeenCalled();
    });

    test("rifiuta payload null", async () => {
      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: null,
      };

      await expect(
        ensureOneSignalUserHandler(request, API_KEY)
      ).rejects.toMatchObject({ code: "invalid-argument" });
    });
  });

  describe("Creazione utente", () => {
    test("crea un utente con email subscription", async () => {
      fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {
        identity: { external_id: "user-1", onesignal_id: "abc" },
      }));

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { externalId: "user-1", email: "test@example.com" },
      };

      const result = await ensureOneSignalUserHandler(request, API_KEY);

      expect(fetchMock).toHaveBeenCalledTimes(1);
      expect(fetchMock).toHaveBeenCalledWith(
        ONESIGNAL_USERS_URL,
        expect.objectContaining({ method: "POST" })
      );

      const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
      expect(sentBody.identity).toEqual({ external_id: "user-1" });
      expect(sentBody.subscriptions).toEqual([
        { type: "Email", token: "test@example.com", enabled: true },
      ]);

      expect(result).toMatchObject({ identity: { external_id: "user-1" } });
    });

    test("crea un utente senza subscriptions se email mancante", async () => {
      fetchMock.mockResolvedValueOnce(mockFetchResponse(200, { ok: true }));

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { externalId: "user-1" },
      };

      await ensureOneSignalUserHandler(request, API_KEY);

      const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
      expect(sentBody.subscriptions).toBeUndefined();
    });

    test("usa header Authorization: Key <apiKey>", async () => {
      fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {}));

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { externalId: "user-1" },
      };

      await ensureOneSignalUserHandler(request, API_KEY);

      const headers = fetchMock.mock.calls[0][1].headers;
      expect(headers.Authorization).toBe(`Key ${API_KEY}`);
    });

    test("trimma eventuali spazi nell'email", async () => {
      fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {}));

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { externalId: "user-1", email: "  test@example.com  " },
      };

      await ensureOneSignalUserHandler(request, API_KEY);

      const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
      expect(sentBody.subscriptions[0].token).toBe("test@example.com");
    });

    test("non imposta l'app_id nel body (è nell'URL)", async () => {
      fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {}));

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { externalId: "user-1" },
      };

      await ensureOneSignalUserHandler(request, API_KEY);

      const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
      expect(sentBody.app_id).toBeUndefined();
      // Verifica che l'URL contenga l'app_id
      expect(fetchMock.mock.calls[0][0]).toContain(ONESIGNAL_APP_ID);
    });
  });

  describe("Utente già esistente (409)", () => {
    test("aggiunge l'email subscription se l'utente esiste già", async () => {
      // Prima chiamata: POST /users → 409
      fetchMock.mockResolvedValueOnce(mockFetchResponse(409, {
        errors: ["User with external_id already exists"],
      }));
      // Seconda chiamata: POST /users/by/external_id/.../subscriptions → 200
      fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {
        subscription: { id: "sub-1", type: "Email" },
      }));

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { externalId: "user-1", email: "test@example.com" },
      };

      const result = await ensureOneSignalUserHandler(request, API_KEY);

      expect(fetchMock).toHaveBeenCalledTimes(2);

      // La seconda chiamata deve essere all'endpoint subscriptions
      const secondCallUrl = fetchMock.mock.calls[1][0];
      expect(secondCallUrl).toContain("/users/by/external_id/user-1/subscriptions");

      const secondCallBody = JSON.parse(fetchMock.mock.calls[1][1].body);
      expect(secondCallBody.subscription).toEqual({
        type: "Email",
        token: "test@example.com",
        enabled: true,
      });

      expect(result).toMatchObject({ alreadyExisted: true });
    });

    test("accetta 409 anche sull'endpoint subscriptions (email già presente)", async () => {
      fetchMock.mockResolvedValueOnce(mockFetchResponse(409, {})); // users
      fetchMock.mockResolvedValueOnce(mockFetchResponse(409, {})); // subscriptions
      fetchMock.mockResolvedValueOnce(mockFetchResponse(202, { success: true })); // re-enable

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { externalId: "user-1", email: "test@example.com" },
      };

      const result = await ensureOneSignalUserHandler(request, API_KEY);
      expect(fetchMock).toHaveBeenCalledTimes(3);
      expect(fetchMock.mock.calls[2][0]).toBe(
        `${ONESIGNAL_SUBSCRIPTIONS_BY_TOKEN_URL}/Email/test%40example.com`
      );
      expect(JSON.parse(fetchMock.mock.calls[2][1].body)).toEqual({
        subscription: {
          enabled: true,
          notification_types: 1,
        },
      });
      expect(result).toMatchObject({ alreadyExisted: true, reenabled: true });
    });

    test("lancia errore se 409 senza email (non può aggiungere subscription)", async () => {
      fetchMock.mockResolvedValueOnce(mockFetchResponse(409, {
        errors: ["already exists"],
      }));

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { externalId: "user-1" },
      };

      await expect(
        ensureOneSignalUserHandler(request, API_KEY)
      ).rejects.toMatchObject({ code: "internal" });
      expect(fetchMock).toHaveBeenCalledTimes(1);
    });

    test("encoda correttamente external_id con caratteri speciali", async () => {
      fetchMock.mockResolvedValueOnce(mockFetchResponse(409, {}));
      fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {}));

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { externalId: "user with/slash", email: "test@example.com" },
      };

      await ensureOneSignalUserHandler(request, API_KEY);

      const subUrl = fetchMock.mock.calls[1][0];
      expect(subUrl).toContain("user%20with%2Fslash");
    });
  });

  describe("Gestione errori", () => {
    test("lancia HttpsError internal su risposta errore diversa da 409", async () => {
      fetchMock.mockResolvedValueOnce(mockFetchResponse(400, {
        errors: ["Invalid email format"],
      }));

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { externalId: "user-1", email: "invalid" },
      };

      await expect(
        ensureOneSignalUserHandler(request, API_KEY)
      ).rejects.toMatchObject({
        code: "internal",
        message: expect.stringContaining("Invalid email"),
      });
    });

    test("lancia HttpsError unavailable se fetch fallisce", async () => {
      fetchMock.mockRejectedValueOnce(new Error("Network down"));

      const request: HandlerRequest = {
        auth: { uid: "user-1" },
        data: { externalId: "user-1", email: "test@example.com" },
      };

      await expect(
        ensureOneSignalUserHandler(request, API_KEY)
      ).rejects.toMatchObject({ code: "unavailable" });
    });
  });
});

describe("removeOneSignalEmailHandler", () => {
  let fetchMock: jest.Mock;

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  function mockFetchResponse(status: number, data: Record<string, unknown>) {
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => data,
    } as Response;
  }

  test("rifiuta richieste non autenticate", async () => {
    const request: HandlerRequest = {
      auth: null,
      data: { email: "test@example.com" },
    };

    await expect(
      removeOneSignalEmailHandler(request, API_KEY)
    ).rejects.toMatchObject({ code: "unauthenticated" });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("rifiuta payload senza email", async () => {
    const request: HandlerRequest = {
      auth: { uid: "user-1" },
      data: {},
    };

    await expect(
      removeOneSignalEmailHandler(request, API_KEY)
    ).rejects.toMatchObject({ code: "invalid-argument" });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("considera già rimossa la subscription se l'utente OneSignal non esiste", async () => {
    fetchMock.mockResolvedValueOnce(mockFetchResponse(404, {}));

    const request: HandlerRequest = {
      auth: { uid: "user-1" },
      data: { email: "test@example.com" },
    };

    const result = await removeOneSignalEmailHandler(request, API_KEY);
    expect(result).toMatchObject({ alreadyRemoved: true, reason: "user_not_found" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  test("considera già rimossa la subscription se l'email non è presente", async () => {
    fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {
      subscriptions: [
        { id: "sub-push-1", type: "iOSPush", token: "push-token", enabled: true },
      ],
    }));

    const request: HandlerRequest = {
      auth: { uid: "user-1" },
      data: { email: "test@example.com" },
    };

    const result = await removeOneSignalEmailHandler(request, API_KEY);
    expect(result).toMatchObject({ alreadyRemoved: true, reason: "email_not_found" });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  test("disabilita la subscription email trovata sull'utente autenticato", async () => {
    fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {
      subscriptions: [
        { id: "sub-email-1", type: "Email", token: "test@example.com", enabled: true },
      ],
    }));
    fetchMock.mockResolvedValueOnce(mockFetchResponse(202, { success: true }));

    const request: HandlerRequest = {
      auth: { uid: "user-1" },
      data: { email: "test@example.com" },
    };

    const result = await removeOneSignalEmailHandler(request, API_KEY);

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[0][0]).toBe(
      `${ONESIGNAL_USERS_URL}/by/external_id/user-1`
    );
    expect(fetchMock.mock.calls[1][0]).toBe(
      `${ONESIGNAL_SUBSCRIPTIONS_URL}/sub-email-1`
    );
    expect(JSON.parse(fetchMock.mock.calls[1][1].body)).toEqual({
      subscription: {
        enabled: false,
        notification_types: -2,
      },
    });
    expect(result).toMatchObject({ success: true, subscriptionId: "sub-email-1" });
  });

  test("non patcha se la subscription email è già disabilitata", async () => {
    fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {
      subscriptions: [
        { id: "sub-email-1", type: "Email", token: "test@example.com", enabled: false },
      ],
    }));

    const request: HandlerRequest = {
      auth: { uid: "user-1" },
      data: { email: "test@example.com" },
    };

    const result = await removeOneSignalEmailHandler(request, API_KEY);
    expect(result).toMatchObject({
      alreadyRemoved: true,
      reason: "already_disabled",
      subscriptionId: "sub-email-1",
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

describe("Guardrail OneSignal staging", () => {
  let fetchMock: jest.Mock;
  const originalAppEnv = process.env.APP_ENV;
  const originalAllowlist = process.env.STAGING_NOTIFICATION_EMAIL_ALLOWLIST;

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
    process.env.APP_ENV = "staging";
    process.env.STAGING_NOTIFICATION_EMAIL_ALLOWLIST = "test.staging@example.com";
  });

  afterEach(() => {
    if (originalAppEnv === undefined) delete process.env.APP_ENV;
    else process.env.APP_ENV = originalAppEnv;
    if (originalAllowlist === undefined) delete process.env.STAGING_NOTIFICATION_EMAIL_ALLOWLIST;
    else process.env.STAGING_NOTIFICATION_EMAIL_ALLOWLIST = originalAllowlist;
    jest.clearAllMocks();
  });

  test("sopprime una notifica indirizzata a un UID non sintetico", async () => {
    const result = await sendOneSignalNotificationHandler(
      { auth: { uid: "stg_admin" }, data: { include_aliases: { external_id: ["user-production"] } } },
      API_KEY,
      makeDeps()
    );

    expect(result).toEqual({ suppressed: true });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("sopprime una email fuori allowlist", async () => {
    const result = await sendOneSignalNotificationHandler(
      {
        auth: { uid: "stg_admin" },
        data: {
          include_aliases: { external_id: ["stg_user"] },
          target_channel: "email",
        },
      },
      API_KEY,
      makeDeps({ users: { stg_user: { email: "not-allowed@example.com" } } })
    );

    expect(result).toEqual({ suppressed: true });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("marca e inoltra solo notifiche per UID sintetici", async () => {
    fetchMock.mockResolvedValue({
      ok: true, status: 200, json: async () => ({ id: "staging-notification" }),
    } as Response);

    await sendOneSignalNotificationHandler(
      {
        auth: { uid: "stg_admin" },
        data: {
          include_aliases: { external_id: ["stg_user"] },
          email_subject: "Avviso",
          contents: { it: "Messaggio" },
        },
      },
      API_KEY,
      makeDeps()
    );

    const body = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(body.email_subject).toBe("[STAGING] Avviso");
    expect(body.contents.it).toBe("[STAGING] Messaggio");
  });

  test("non crea subscription fuori dalla email allowlist", async () => {
    const result = await ensureOneSignalEmailSubscription(
      "stg_user", "not-allowed@example.com", API_KEY
    );

    expect(result).toEqual({ suppressed: true });
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

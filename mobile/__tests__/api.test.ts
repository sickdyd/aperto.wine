import type { AxiosError } from "axios";
import { normaliseError } from "@/services/api";

const asAxiosError = (partial: Partial<AxiosError>) => partial as AxiosError;

describe("normaliseError", () => {
  it("reports a missing response as a network error", () => {
    const result = normaliseError(asAxiosError({ response: undefined }));
    expect(result.code).toBe("network_error");
    expect(result.status).toBeUndefined();
  });

  it("passes through the server's own error envelope", () => {
    const result = normaliseError(
      asAxiosError({
        response: {
          status: 401,
          data: { error: { code: "token_expired", message: "Token expired" } },
        },
      } as Partial<AxiosError>),
    );
    expect(result).toEqual({ code: "token_expired", message: "Token expired", status: 401 });
  });

  it("does not invent a code when something upstream answers with HTML", () => {
    // A 502 from a load balancer is not our envelope. Reporting it as
    // "unexpected_response" keeps the real cause visible instead of
    // mislabelling it as an application error.
    const result = normaliseError(
      asAxiosError({
        response: { status: 502, data: "<html>Bad Gateway</html>" },
      } as Partial<AxiosError>),
    );
    expect(result.code).toBe("unexpected_response");
    expect(result.status).toBe(502);
  });

  it("distinguishes a 404 from other malformed responses", () => {
    const result = normaliseError(
      asAxiosError({ response: { status: 404, data: "" } } as Partial<AxiosError>),
    );
    expect(result.code).toBe("not_found");
  });
});

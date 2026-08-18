import { z } from "zod";

/**
 * The error envelope every api/v1 endpoint uses, mirroring the shape jeero's
 * Api::V1::BaseController renders from its rescue_from handlers. Parsing rather
 * than trusting it means a proxy returning an HTML error page surfaces as a
 * schema failure here instead of as `undefined.code` three layers up.
 */
export const apiErrorSchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
  }),
});

export type ApiError = z.infer<typeof apiErrorSchema>;

export const authTokensSchema = z.object({
  access_token: z.string(),
  refresh_token: z.string(),
});

export type AuthTokens = z.infer<typeof authTokensSchema>;

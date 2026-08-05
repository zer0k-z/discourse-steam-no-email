export const PLACEHOLDER_EMAIL_SUFFIX = "@steam.invalid";

export function isPlaceholderEmail(email) {
  return Boolean(email?.endsWith(PLACEHOLDER_EMAIL_SUFFIX));
}

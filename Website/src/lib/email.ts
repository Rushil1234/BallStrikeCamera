// Reserved / guaranteed-undeliverable email domains (RFC 2606 & 6761). `example.com`,
// `example.org`, `example.net` publish a Null MX record, and `.test` / `.invalid` /
// `.localhost` / `.example` never resolve — so any confirmation email GoTrue sends to one
// HARD-bounces back to our SMTP sender's inbox. Reject them BEFORE calling signUp so no
// account is created and no email is ever sent. (The same rule is enforced server-side by
// migration 062 so it also blocks API-direct signups, but this gives real users instant,
// friendly feedback instead of a raw error.)

const RESERVED_DOMAINS = new Set(["example.com", "example.org", "example.net", "localhost"]);
const RESERVED_TLDS = new Set(["test", "example", "invalid", "localhost"]);

/** True when the email's domain can never receive mail (reserved per RFC 2606 / 6761). */
export function isUndeliverableEmail(email: string): boolean {
  const at = email.lastIndexOf("@");
  if (at < 0) return false;
  const domain = email.slice(at + 1).trim().toLowerCase();
  if (!domain) return false;
  if (RESERVED_DOMAINS.has(domain)) return true;
  const tld = domain.slice(domain.lastIndexOf(".") + 1);
  return RESERVED_TLDS.has(tld);
}

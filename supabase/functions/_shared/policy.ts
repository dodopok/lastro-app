// Regras do piloto automático. Puras e testadas (policy_test.ts): o servidor
// é a fonte da verdade. O app só mostra o que vier daqui.

export type PaymentDecision =
  | { status: "processing" }
  | { status: "awaiting_approval"; reason: string }
  | { status: "blocked"; reason: string };

export interface DecisionInput {
  amountCents: number;
  /** Saldo confirmado do mês: renda − tudo que já foi confirmado. */
  balanceCents: number;
  /** Trava de segurança: nada é pago se o saldo ficar abaixo disto. */
  floorCents: number;
  /** Acima disto, o app pede Face ID antes de mandar. */
  approvalThresholdCents: number;
  /** O cliente pode exigir aprovação mesmo abaixo do limite. */
  forceApproval?: boolean;
  /** Já aprovado com Face ID (passo 2 do fluxo). */
  approved?: boolean;
}

export function decide(i: DecisionInput): PaymentDecision {
  if (!Number.isInteger(i.amountCents) || i.amountCents <= 0) {
    throw new RangeError("valor inválido");
  }
  if (i.balanceCents - i.amountCents < i.floorCents) {
    return {
      status: "blocked",
      reason: `saldo ficaria abaixo da trava (${brl(i.floorCents)})`,
    };
  }
  if (!i.approved && (i.forceApproval || i.amountCents > i.approvalThresholdCents)) {
    return {
      status: "awaiting_approval",
      reason: `acima de ${brl(i.approvalThresholdCents)}: precisa de Face ID`,
    };
  }
  return { status: "processing" };
}

export function brl(cents: number): string {
  const sign = cents < 0 ? "−" : "";
  const v = Math.abs(cents) / 100;
  return sign + "R$ " + v.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/** Primeiro dia do mês (YYYY-MM-01) de uma data no fuso do usuário. */
export function monthOf(date: Date, timeZone = "America/Sao_Paulo"): string {
  const [y, m] = localParts(date, timeZone);
  return `${y}-${m}-01`;
}

export function dayOf(date: Date, timeZone = "America/Sao_Paulo"): number {
  return Number(localParts(date, timeZone)[2]);
}

function localParts(date: Date, timeZone: string): [string, string, string] {
  const s = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" })
    .format(date); // 2026-09-21
  const [y, m, d] = s.split("-");
  return [y, m, d];
}

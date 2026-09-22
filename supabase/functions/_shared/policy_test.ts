import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { brl, dayOf, decide, monthOf } from "./policy.ts";

const base = { balanceCents: 876807, floorCents: 300000, approvalThresholdCents: 100000 };

Deno.test("abaixo de R$ 1.000 paga direto", () => {
  assertEquals(decide({ ...base, amountCents: 36000 }).status, "processing");
});

Deno.test("acima de R$ 1.000 pede Face ID (Ajuda ao Matheus)", () => {
  assertEquals(decide({ ...base, amountCents: 209000 }).status, "awaiting_approval");
});

Deno.test("depois de aprovado, segue", () => {
  assertEquals(decide({ ...base, amountCents: 209000, approved: true }).status, "processing");
});

Deno.test("exigeAprovacao força Face ID mesmo abaixo do limite", () => {
  assertEquals(decide({ ...base, amountCents: 5000, forceApproval: true }).status, "awaiting_approval");
});

Deno.test("trava: não paga se o saldo cair abaixo do mínimo", () => {
  const d = decide({ ...base, amountCents: 600000, approved: true });
  assertEquals(d.status, "blocked");
});

Deno.test("trava vence a aprovação", () => {
  assertEquals(decide({ ...base, balanceCents: 310000, amountCents: 20000 }).status, "blocked");
});

Deno.test("valor precisa ser inteiro positivo", () => {
  assertThrows(() => decide({ ...base, amountCents: 0 }));
  assertThrows(() => decide({ ...base, amountCents: 10.5 }));
});

Deno.test("formatação e datas no fuso de Brasília", () => {
  assertEquals(brl(209000), "R$ 2.090,00");
  assertEquals(brl(-21000), "−R$ 210,00");
  // 02:30 UTC do dia 1º ainda é dia 30 do mês anterior em São Paulo
  const d = new Date("2026-10-01T02:30:00Z");
  assertEquals(monthOf(d), "2026-09-01");
  assertEquals(dayOf(d), 30);
});

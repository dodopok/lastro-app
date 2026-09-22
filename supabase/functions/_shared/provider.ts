// Provedor de pagamento. A v1 usa o sandbox; um provedor real (PSP / banco
// com API Pix) entra implementando PaymentProvider e mudando PAYMENT_PROVIDER.

export interface PaymentOrder {
  id: string;
  method: "pix" | "boleto";
  amountCents: number;
  /** Chave Pix ou linha digitável do boleto. */
  destination: string;
  idempotencyKey: string;
}

export type PaymentResult =
  | { status: "paid"; providerRef: string }
  | { status: "processing"; providerRef: string }
  | { status: "failed"; reason: string };

export interface PaymentProvider {
  readonly name: string;
  send(order: PaymentOrder): Promise<PaymentResult>;
}

/** Não move dinheiro. Paga na hora; destino contendo "falha" simula erro. */
export class SandboxProvider implements PaymentProvider {
  readonly name = "sandbox";

  send(order: PaymentOrder): Promise<PaymentResult> {
    if (order.destination.includes("falha")) {
      return Promise.resolve({ status: "failed", reason: "sandbox: destino recusado" });
    }
    return Promise.resolve({ status: "paid", providerRef: `sbx_${order.idempotencyKey}` });
  }
}

export function providerFromEnv(get: (k: string) => string | undefined): PaymentProvider {
  const name = get("PAYMENT_PROVIDER") ?? "sandbox";
  switch (name) {
    case "sandbox":
      return new SandboxProvider();
    default:
      throw new Error(`PAYMENT_PROVIDER desconhecido: ${name}`);
  }
}

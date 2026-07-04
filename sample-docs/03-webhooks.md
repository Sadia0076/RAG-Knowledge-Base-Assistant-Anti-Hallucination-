# Webhooks

Webhooks notify your application whenever an event happens.

## Configuring Webhooks

Register your webhook endpoint in the Stripe Dashboard.

## Verifying Signatures

Every webhook request includes a Stripe-Signature header.

Always verify this signature before processing the request.

## Common Events

payment_intent.succeeded

payment_intent.failed

charge.refunded

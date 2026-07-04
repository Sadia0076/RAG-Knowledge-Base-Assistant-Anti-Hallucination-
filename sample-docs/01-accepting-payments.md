# Accepting Payments

This guide explains how businesses can start accepting online payments using Stripe.

## Supported Payment Methods

Stripe supports credit cards, debit cards, Apple Pay, Google Pay, ACH transfers, and bank payments depending on the region.

## Creating a Checkout Session

Create a Checkout Session using the Stripe API and redirect customers to the hosted payment page.

## Payment Confirmation

After a successful payment, Stripe returns a success response and sends webhook events for confirmation.

## Best Practices

Always verify payment status using webhooks instead of relying only on the client response.

import { useState } from "react";
import { Alert, Badge, Box, Button, Card, Flex, HStack, Input, List, Spinner, Table, Text, Textarea } from "@chakra-ui/react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { api, money, refreshAfterWrite, Review, ShipStats, Unblock } from "../api";
import ReviewDialog from "../components/ReviewDialog";
import ActionBar from "../components/ActionBar";

type Card_ = { include: boolean; qty: Record<string, number>; justification: string };
type Outcome = Awaited<ReturnType<typeof api.commitUnblock>>;

const runs = (s: ShipStats | null | undefined) =>
  !s ? "–" : `${s.shippedInRuns} of ${s.runs} runs${s.medianMinutes != null ? `, ~${Math.round(s.medianMinutes)} min` : ""}`;

const statusColor = (s: string) =>
  s === "freed by the extra" ? "green" : s === "frees itself" ? "blue" : s === "can't be freed by buying" ? "red" : "orange";

/** Customer orders stuck behind smaller ones, and the priority POs that would free them. The proposal comes from
 *  playing the business forward on a copy of the live graph in Relate (sandbox/unblock.py); nothing is written to
 *  Aura until a person reviews and confirms. */
export default function Stuck({ drafts }: { drafts: boolean }) {
  const qc = useQueryClient();
  const stuck = useQuery({ queryKey: ["stuck"], queryFn: api.stuckOrders });
  const [sim, setSim] = useState<Unblock | null>(null);
  const [simulating, setSimulating] = useState(false);
  const [cards, setCards] = useState<Record<string, Card_>>({});
  const [review, setReview] = useState<Review | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [drafting, setDrafting] = useState<string | null>(null);

  const simulate = async () => {
    setSimulating(true); setError(null); setOutcome(null);
    try {
      const r = await api.simulateUnblock();
      setSim(r);
      setCards(Object.fromEntries(r.proposals.map((p) => [p.supplierId, {
        include: true, qty: Object.fromEntries(p.lines.map((l) => [l.productId, l.extra])), justification: p.priorityLine,
      }])));
    } catch (e) { setError((e as Error).message); }
    finally { setSimulating(false); }
  };

  const set = (sid: string, patch: Partial<Card_>) => setCards({ ...cards, [sid]: { ...cards[sid], ...patch } });
  const included = (sim?.proposals ?? []).filter((p) => cards[p.supplierId]?.include);
  const items = (sid: string) => Object.entries(cards[sid].qty).filter(([, q]) => q > 0).map(([productId, qty]) => ({ productId, qty }));

  const toReview = async () => {
    setError(null);
    try {
      setReview(await api.previewUnblock(included.map((p) => ({
        supplierId: p.supplierId, items: items(p.supplierId), justification: cards[p.supplierId].justification,
      }))));
    } catch (e) { setError((e as Error).message); }
  };

  const confirm = async (previewId: string) => {
    const out = await api.commitUnblock(previewId);
    setReview(null); setOutcome(out); setSim(null);
    refreshAfterWrite(qc);
  };

  const suggest = async (sid: string) => {
    setDrafting(sid);
    try { set(sid, { justification: (await api.draft({ kind: "unblock", supplierId: sid, items: items(sid) })).draft }); }
    catch (e) { setError((e as Error).message); }
    finally { setDrafting(null); }
  };

  if (stuck.isLoading) return <Spinner mt={6} />;
  if (stuck.error) return <Text color="red.500" mt={4}>{(stuck.error as Error).message}</Text>;
  const st = stuck.data!;
  const a = sim?.assumptions;

  return (
    <Box pt={4}>
      <Flex justify="space-between" align="start" mb={3} gap={4}>
        <Text color="fg.muted" fontSize="sm">
          The warehouse ships the oldest order whose every line is in stock, so a large order can wait while smaller
          ones ship first and use each delivery up. An order is <b>stuck</b> when it has waited more than {st.stuckFactor}×
          the usual time to ship{st.pace.MedianShipMinutes != null ? ` (${st.pace.MedianShipMinutes} min, so after
          ${Math.round(st.stuckFactor * st.pace.MedianShipMinutes)} min)` : ""}, measured over the last {st.windowDays} days
          {st.orderIdPrefix ? <> and counting only the simulation's orders (IDs starting with <b>{st.orderIdPrefix}</b>);
          the imported historical orders are left out, though they still compete for stock in the simulation</> : null}.
        </Text>
        <HStack>
          {stuck.isFetching && <><Spinner size="xs" /><Text fontSize="xs" color="fg.muted">Reloading…</Text></>}
          <Button size="sm" variant="outline" disabled={stuck.isFetching}
                  onClick={() => { setSim(null); setOutcome(null); qc.invalidateQueries({ queryKey: ["stuck"] }); }}>
            Reload from the graph
          </Button>
        </HStack>
      </Flex>

      {outcome && (
        <Alert.Root status="success" mb={3}><Alert.Indicator />
          <Alert.Content>
            <Alert.Title>Created {outcome.created.length} priority PO(s). The lists are reloaded from the graph.</Alert.Title>
            <Alert.Description><List.Root ps={4}>
              {outcome.created.map((c) => <List.Item key={c.PONumber}>{c.PONumber}: est. {money(c.EstimatedCost)}, goes to {c.approvalLevel}, unblocks {c.unblocks.join(", ")}</List.Item>)}
              {outcome.left_out.map((l, i) => <List.Item key={i}>Left out {l.product}: {l.reason}</List.Item>)}
            </List.Root></Alert.Description>
          </Alert.Content>
        </Alert.Root>
      )}

      {st.rows.length === 0 && <Text mt={4}>No customer order is stuck right now.</Text>}
      {st.rows.length > 0 && (
        <Table.Root size="sm" variant="outline" mb={4}>
          <Table.Header><Table.Row>
            <Table.ColumnHeader>Order</Table.ColumnHeader><Table.ColumnHeader>Customer</Table.ColumnHeader>
            <Table.ColumnHeader textAlign="end">Waiting</Table.ColumnHeader><Table.ColumnHeader textAlign="end">Value</Table.ColumnHeader>
            <Table.ColumnHeader>Lines (ordered / in stock)</Table.ColumnHeader>
            {sim && <Table.ColumnHeader>Outcome (simulated)</Table.ColumnHeader>}
          </Table.Row></Table.Header>
          <Table.Body>
            {st.rows.map((o) => {
              const r = sim?.orders.find((x) => x.OrderID === o.OrderID);
              return (
                <Table.Row key={o.OrderID}>
                  <Table.Cell>{o.OrderID}{o.PastRequiredDate && <Badge ml={2} colorPalette="red">past required date</Badge>}</Table.Cell>
                  <Table.Cell>{o.Customer}</Table.Cell>
                  <Table.Cell textAlign="end">{o.WaitingHours} h</Table.Cell>
                  <Table.Cell textAlign="end">{money(o.Value)}</Table.Cell>
                  <Table.Cell fontSize="xs">
                    {o.Lines.map((l) => (
                      <Text as="span" key={l.ProductID} color={l.Short ? "red.600" : undefined} mr={3}>
                        {l.Product} {l.Ordered}/{l.InStock}
                      </Text>
                    ))}
                  </Table.Cell>
                  {sim && (
                    <Table.Cell fontSize="xs">
                      {r ? (<>
                        <Badge colorPalette={statusColor(r.status)}>{r.status}</Badge>
                        <Box>as things stand: ships in {runs(r.withoutExtra)}</Box>
                        {r.withExtra && <Box>with the proposed extra: {runs(r.withExtra)}</Box>}
                        {r.withNaiveExtra && <Box>ordering only what's missing today: {runs(r.withNaiveExtra)}</Box>}
                        <Box>reserving stock instead: {runs(r.withReservation)}</Box>
                      </>) : "–"}
                    </Table.Cell>
                  )}
                </Table.Row>
              );
            })}
          </Table.Body>
        </Table.Root>
      )}

      {st.rows.length > 0 && !sim && (
        <Card.Root variant="subtle" mb={4}>
          <Card.Body>
            <Flex justify="space-between" align="center" gap={4} wrap="wrap">
              <Text fontSize="sm">
                Copies the open orders, stock and incoming POs into a scratch <b>Relate</b> store and plays the business
                forward with the warehouse's own rule, to find how much would have to arrive for these orders to ship.
                Nothing is written to Aura. Takes a few seconds.
              </Text>
              <Button colorPalette="blue" loading={simulating} loadingText="Playing the business forward…" onClick={simulate}>
                Find what would free them
              </Button>
            </Flex>
          </Card.Body>
        </Card.Root>
      )}

      {sim?.message && <Text mb={3}>{sim.message}</Text>}
      {sim?.history && sim.history.notes.length > 0 && (
        <Alert.Root status="warning" mb={3}>
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>Little history yet: these quantities are probably low</Alert.Title>
            <Alert.Description>
              The simulation projects the next hours from the recent past: {sim.history.notes.join("; ")}. As the
              business runs longer the estimates firm up. Until then, order above the simulated quantity, or set a
              safety margin (UNBLOCK_SAFETY_PERCENT in .env).
            </Alert.Description>
          </Alert.Content>
        </Alert.Root>
      )}
      {sim && a && (
        <Text fontSize="xs" color="fg.muted" mb={3}>
          Simulated in Relate ({sim.source?.method}): {a.runs} runs, an extra delivery landing in {a.deliveryMinute} min
          (PO lead time{a.poLeadMeasured ? "" : ", estimated"}), counted as freed if the order ships within {a.horizonMinutes} min;
          {" "}{a.shippedPerHour} orders shipped and {a.receivedPerHour} received per hour
          {a.safetyPercent > 0 ? `; a ${a.safetyPercent}% safety margin is added to the simulated quantities` : ""}. Estimates.
        </Text>
      )}
      {sim?.reservation && (
        <Alert.Root status="info" mb={4}>
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>The alternative rule: reserve stock for the stuck orders, buy nothing extra</Alert.Title>
            <Alert.Description>
              It frees {sim.reservation.stuckFreed} of {sim.reservation.stuckTotal} stuck order(s) within {a?.comparisonMinutes} min,
              and {sim.reservation.otherOrdersDelayed} other order(s) ship later than they would have
              ({sim.reservation.otherOrdersShippedWith} instead of {sim.reservation.otherOrdersShippedWithout}).
            </Alert.Description>
          </Alert.Content>
        </Alert.Root>
      )}

      {sim?.proposals.map((p) => {
        const c = cards[p.supplierId];
        if (!c) return null;
        return (
          <Card.Root key={p.supplierId} variant="outline" mb={4} opacity={c.include ? 1 : 0.55}>
            <Card.Header pb={2}>
              <Flex justify="space-between" align="start" gap={3} wrap="wrap">
                <Box>
                  <HStack><Badge colorPalette="red">priority</Badge><Text fontWeight="semibold">{p.supplier}</Text></HStack>
                  <Text fontSize="sm" color="fg.muted">Unblocks {p.unblocks.join(", ")}</Text>
                </Box>
                <HStack>
                  <Badge>est. {money(p.estimatedCost)}</Badge><Badge>needs {p.approvalLevel}</Badge>
                  <Button size="xs" variant={c.include ? "outline" : "solid"} onClick={() => set(p.supplierId, { include: !c.include })}>
                    {c.include ? "Leave out" : "Include"}
                  </Button>
                </HStack>
              </Flex>
            </Card.Header>
            <Card.Body pt={0}>
              <Table.Root size="sm" variant="line">
                <Table.Header><Table.Row>
                  <Table.ColumnHeader>Product</Table.ColumnHeader>
                  <Table.ColumnHeader textAlign="end">Stuck orders need</Table.ColumnHeader>
                  <Table.ColumnHeader textAlign="end">In stock now</Table.ColumnHeader>
                  <Table.ColumnHeader textAlign="end">On order</Table.ColumnHeader>
                  <Table.ColumnHeader textAlign="end">Expected when it lands</Table.ColumnHeader>
                  <Table.ColumnHeader textAlign="end">Missing today</Table.ColumnHeader>
                  <Table.ColumnHeader textAlign="end">Simulated</Table.ColumnHeader>
                  <Table.ColumnHeader textAlign="end">Order</Table.ColumnHeader>
                  <Table.ColumnHeader textAlign="end">3-day demand</Table.ColumnHeader>
                </Table.Row></Table.Header>
                <Table.Body>
                  {p.lines.map((l) => (
                    <Table.Row key={l.productId}>
                      <Table.Cell>{l.product}</Table.Cell>
                      <Table.Cell textAlign="end">{l.stuckQty}</Table.Cell>
                      <Table.Cell textAlign="end">{l.stockNow}</Table.Cell>
                      <Table.Cell textAlign="end">{l.onOrder}</Table.Cell>
                      <Table.Cell textAlign="end">{l.stockAtDeliveryMedian}</Table.Cell>
                      <Table.Cell textAlign="end">{l.naiveExtra}</Table.Cell>
                      <Table.Cell textAlign="end">
                        <b>{l.extra}</b>
                        {l.extra !== l.simulatedExtra && <Text as="span" fontSize="xs" color="fg.muted"> ({l.simulatedExtra} + margin)</Text>}
                      </Table.Cell>
                      <Table.Cell textAlign="end">
                        <Input size="xs" w="80px" type="number" min={0} value={c.qty[l.productId] ?? 0} disabled={!c.include}
                               onChange={(e) => set(p.supplierId, { qty: { ...c.qty, [l.productId]: Math.max(0, Math.floor(Number(e.target.value) || 0)) } })} />
                      </Table.Cell>
                      <Table.Cell textAlign="end">
                        {l.tolerance3Days}{l.overTolerance && <Badge ml={1} colorPalette="orange">overstock</Badge>}
                      </Table.Cell>
                    </Table.Row>
                  ))}
                </Table.Body>
              </Table.Root>
              {c.include && (
                <Box mt={3}>
                  <Flex justify="space-between" align="center" mb={1}>
                    <Text fontSize="sm" fontWeight="medium">Justification (starts with PRIORITY: so the approvers see it)</Text>
                    {drafts && <Button size="xs" variant="outline" loading={drafting === p.supplierId} onClick={() => suggest(p.supplierId)}>Suggest (AI draft)</Button>}
                  </Flex>
                  <Textarea size="sm" rows={3} value={c.justification} onChange={(e) => set(p.supplierId, { justification: e.target.value })} />
                </Box>
              )}
            </Card.Body>
          </Card.Root>
        );
      })}

      {error && <Alert.Root status="error" mb={3}><Alert.Indicator /><Alert.Description>{error}</Alert.Description></Alert.Root>}
      {sim && sim.proposals.length > 0 && (
        <ActionBar>
          <Text fontSize="sm" color="fg.muted">{included.length} of {sim.proposals.length} priority PO(s) included</Text>
          <Button colorPalette="blue" disabled={!included.length} onClick={toReview}>Review {included.length} priority PO(s)</Button>
        </ActionBar>
      )}
      <ReviewDialog review={review} verb="Create priority POs" onClose={() => setReview(null)} onConfirm={confirm} />
    </Box>
  );
}

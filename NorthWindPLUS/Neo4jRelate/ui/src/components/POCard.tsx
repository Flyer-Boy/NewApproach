import { ReactNode, useEffect, useState } from "react";
import { Badge, Box, Button, Card, Flex, HStack, Input, Table, Text, Textarea } from "@chakra-ui/react";
import { api, Demand, Item, money } from "../api";

export type CardLine = {
  ProductID: string; Product: string; RecommendedQt: number; UnitsInStock: number; OnActivePOs: number;
  OpenOrderQty: number; StockThreshold: number; RejectedQt?: number;
};

export type CardState = { include: boolean; qty: Record<string, number>; justification: string };

export const initialState = (lines: CardLine[], include = true): CardState => ({
  include,
  qty: Object.fromEntries(lines.filter((l) => l.RecommendedQt > 0).map((l) => [l.ProductID, l.RecommendedQt])),
  justification: "",
});

export const itemsOf = (s: CardState): Item[] =>
  Object.entries(s.qty).filter(([, q]) => q > 0).map(([productId, qty]) => ({ productId, qty }));

const levelColor = (lvl: string) => (lvl === "L1" ? "green" : lvl === "L2" ? "yellow" : lvl === "L3" ? "orange" : "red");

/** One PO being prepared: quantities (recommended by the graph, editable), live demand and cover from the API, and the
 *  justification with an optional AI draft. The approval level shown is the API's, recomputed as quantities change. */
export default function POCard(props: {
  title: string; subtitle?: ReactNode; lines: CardLine[]; demand: Demand | null; state: CardState;
  onChange: (s: CardState) => void; drafts: boolean; draftRequest: () => Promise<string>; actions?: ReactNode;
  showRejected?: boolean;
}) {
  const { lines, state, onChange } = props;
  const [demand, setDemand] = useState<Demand | null>(props.demand);
  const [drafting, setDrafting] = useState(false);
  const [draftError, setDraftError] = useState<string | null>(null);
  const items = itemsOf(state);
  const key = JSON.stringify(items);

  useEffect(() => {
    if (!items.length) { setDemand(null); return; }
    const t = setTimeout(() => { api.demand(items).then(setDemand).catch(() => undefined); }, 400);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);

  const byProduct = Object.fromEntries((demand?.rows ?? []).map((r) => [r.ProductID, r]));
  const setQty = (pid: string, q: number) => onChange({ ...state, qty: { ...state.qty, [pid]: Math.max(0, Math.floor(q || 0)) } });

  const suggest = async () => {
    setDrafting(true);
    setDraftError(null);
    try {
      onChange({ ...state, justification: await props.draftRequest() });
    } catch (e) {
      setDraftError((e as Error).message);
    } finally {
      setDrafting(false);
    }
  };

  return (
    <Card.Root variant="outline" opacity={state.include ? 1 : 0.55} mb={4}>
      <Card.Header pb={2}>
        <Flex justify="space-between" align="start" gap={3} wrap="wrap">
          <Box>
            <Text fontWeight="semibold">{props.title}</Text>
            {props.subtitle && <Box fontSize="sm" color="fg.muted">{props.subtitle}</Box>}
          </Box>
          <HStack>
            {demand && (
              <>
                <Badge colorPalette="gray">est. {money(demand.po.estimatedCost)}</Badge>
                <Badge colorPalette={levelColor(demand.po.approvalLevel)}>needs {demand.po.approvalLevel}</Badge>
              </>
            )}
            {props.actions}
          </HStack>
        </Flex>
      </Card.Header>
      <Card.Body pt={0}>
        <Table.Root size="sm" variant="line">
          <Table.Header>
            <Table.Row>
              <Table.ColumnHeader>Product</Table.ColumnHeader>
              {props.showRejected && <Table.ColumnHeader textAlign="end">Rejected</Table.ColumnHeader>}
              <Table.ColumnHeader textAlign="end">Stock / threshold</Table.ColumnHeader>
              <Table.ColumnHeader textAlign="end">On POs</Table.ColumnHeader>
              <Table.ColumnHeader textAlign="end">Open orders</Table.ColumnHeader>
              <Table.ColumnHeader textAlign="end">Recommended</Table.ColumnHeader>
              <Table.ColumnHeader textAlign="end">Order</Table.ColumnHeader>
              <Table.ColumnHeader>Recent demand (graph)</Table.ColumnHeader>
            </Table.Row>
          </Table.Header>
          <Table.Body>
            {lines.map((l) => {
              const d = byProduct[l.ProductID];
              const needed = l.RecommendedQt > 0;
              return (
                <Table.Row key={l.ProductID}>
                  <Table.Cell>{l.Product}</Table.Cell>
                  {props.showRejected && <Table.Cell textAlign="end">{l.RejectedQt}</Table.Cell>}
                  <Table.Cell textAlign="end">{l.UnitsInStock} / {l.StockThreshold}</Table.Cell>
                  <Table.Cell textAlign="end">{l.OnActivePOs}</Table.Cell>
                  <Table.Cell textAlign="end">{l.OpenOrderQty}</Table.Cell>
                  <Table.Cell textAlign="end">{needed ? l.RecommendedQt : "not needed"}</Table.Cell>
                  <Table.Cell textAlign="end">
                    {needed ? (
                      <Input size="xs" w="90px" type="number" min={0} value={state.qty[l.ProductID] ?? 0}
                             disabled={!state.include} onChange={(e) => setQty(l.ProductID, Number(e.target.value))} />
                    ) : "–"}
                  </Table.Cell>
                  <Table.Cell fontSize="xs">
                    {!d ? "–" : d.Orders === 0 ? "no orders in the window" : (
                      <>
                        {d.UnitsPerDay}/day over {d.DaysObserved} d · covers {d.DaysOfCoverAfterPO ?? "–"} d
                        {d.SuggestedQt != null && state.include && (
                          <Button size="2xs" variant="subtle" colorPalette="blue" ml={2}
                                  onClick={() => setQty(l.ProductID, d.SuggestedQt!)}>
                            {demand?.coverDays} d → {d.SuggestedQt}
                          </Button>
                        )}
                      </>
                    )}
                  </Table.Cell>
                </Table.Row>
              );
            })}
          </Table.Body>
        </Table.Root>
        {demand?.po.anySuggestion && state.include && (
          <Text fontSize="xs" color="fg.muted" mt={2}>
            Covering {demand.coverDays} days of recent demand for every product would cost about{" "}
            {money(demand.po.estimatedCostWithSuggestions)} and need {demand.po.approvalLevelWithSuggestions}.
            Advisory only: the recommendation stays the graph's restock rule.
          </Text>
        )}
        {state.include && (
          <Box mt={3}>
            <Flex justify="space-between" align="center" mb={1}>
              <Text fontSize="sm" fontWeight="medium">Justification (required, recorded with the PO)</Text>
              {props.drafts && (
                <Button size="xs" variant="outline" loading={drafting} onClick={suggest}>Suggest (AI draft)</Button>
              )}
            </Flex>
            <Textarea size="sm" rows={2} value={state.justification}
                      placeholder="Why this PO, in your words. An AI draft is only a starting point: edit it before you submit."
                      onChange={(e) => onChange({ ...state, justification: e.target.value })} />
            {draftError && <Text fontSize="xs" color="red.500">{draftError}</Text>}
          </Box>
        )}
      </Card.Body>
    </Card.Root>
  );
}

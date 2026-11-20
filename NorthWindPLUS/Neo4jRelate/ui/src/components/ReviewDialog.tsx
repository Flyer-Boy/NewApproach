import { useState } from "react";
import { Alert, Badge, Box, Button, Dialog, List, Portal, Stack, Text } from "@chakra-ui/react";
import { money, Review } from "../api";

/** The confirmation step: what the API's prepare step returned (cost, level, recommended vs ordered, flags).
 *  Nothing is written until Confirm; the API checks the review id, its age and the loop guard again on commit. */
export default function ReviewDialog(props: {
  review: Review | null; verb: string; onClose: () => void; onConfirm: (previewId: string) => Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const r = props.review;

  const confirm = async () => {
    if (!r) return;
    setBusy(true);
    setError(null);
    try {
      await props.onConfirm(r.previewId);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog.Root open={!!r} onOpenChange={(e) => { if (!e.open) { setError(null); props.onClose(); } }} size="lg">
      <Portal>
        <Dialog.Backdrop />
        <Dialog.Positioner>
          <Dialog.Content>
            <Dialog.Header><Dialog.Title>{r?.header}</Dialog.Title></Dialog.Header>
            <Dialog.Body>
              <Stack gap={4}>
                {r?.entries.map((e, i) => (
                  <Box key={i} borderWidth="1px" borderRadius="md" p={3}>
                    <Text fontWeight="semibold">{i + 1}. {e.title}</Text>
                    {e.level !== "-" && (
                      <Text fontSize="sm">est. {money(e.cost)} · <Badge>{`needs ${e.level}`}</Badge></Text>
                    )}
                    {e.lines.length > 0 && (
                      <List.Root fontSize="sm" ps={4}>
                        {e.lines.map((l) => (
                          <List.Item key={l.productId}>
                            {l.product}: {l.qty}{l.recommendedQt != null && l.recommendedQt !== l.qty ? ` (recommended ${l.recommendedQt})` : ""}
                          </List.Item>
                        ))}
                      </List.Root>
                    )}
                    <Text fontSize="sm" mt={1}><b>Justification:</b> {e.justification}</Text>
                    {e.flags.map((f) => <Text key={f} fontSize="sm" color="orange.600">⚠ {f}</Text>)}
                  </Box>
                ))}
                {error && (
                  <Alert.Root status="error"><Alert.Indicator /><Alert.Description>{error}</Alert.Description></Alert.Root>
                )}
              </Stack>
            </Dialog.Body>
            <Dialog.Footer>
              <Button variant="outline" onClick={props.onClose}>Back</Button>
              <Button colorPalette="blue" loading={busy} onClick={confirm}>{props.verb}</Button>
            </Dialog.Footer>
          </Dialog.Content>
        </Dialog.Positioner>
      </Portal>
    </Dialog.Root>
  );
}

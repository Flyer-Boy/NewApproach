import { BrowserRouter } from "react-router-dom";
import { ErrorBoundary } from "react-error-boundary";
import { HelmetProvider } from "react-helmet-async";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ChakraProvider } from "@chakra-ui/react";
import theme from "@ride-hailing/theme";
import ErrorPage from "@ride-hailing/components/ErrorPage";
import AppRoutes from "@ride-hailing/routes/AppRoutes";
import { Neo4jProvider } from "use-neo4j";
import neo4j from "neo4j-driver";
import { config } from "@ride-hailing/config";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: false,
      retry: false,
    },
  },
});

const driver = neo4j.driver(
  config.host,
  neo4j.auth.basic(config.username, config.password),
);

const Provider = () => {
  return (
    <ErrorBoundary FallbackComponent={ErrorPage}>
      <QueryClientProvider client={queryClient}>
        <HelmetProvider>
          <ChakraProvider theme={theme}>
            <Neo4jProvider driver={driver} database={config.database}>
              <BrowserRouter>
                <AppRoutes />
              </BrowserRouter>
            </Neo4jProvider>
          </ChakraProvider>
        </HelmetProvider>
      </QueryClientProvider>
    </ErrorBoundary>
  );
};

export default Provider;

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const PlasmaDaTranslationHubModule = buildModule("PlasmaDaTranslationHubModule", (m) => {
  const hub = m.contract('PlasmaDaTranslationHub');
  return { hub }
})

export default PlasmaDaTranslationHubModule
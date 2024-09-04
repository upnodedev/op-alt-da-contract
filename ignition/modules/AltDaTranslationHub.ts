import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const AltDaTranslationHubModule = buildModule("AltDaTranslationHubModule", (m) => {
  const hub = m.contract('AltDaTranslationHub');
  return { hub }
})

export default AltDaTranslationHubModule
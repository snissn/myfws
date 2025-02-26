const fs = require("fs");
const path = require("path");

async function main() {
  // 1) Load the compiled artifact JSON for ServiceFramework
  const sfArtifact = require("../artifacts/contracts/ServiceFramework.sol/ServiceFramework.json");
  
  // 2) Load the artifact for GreetingService
  const greetingArtifact = require("../artifacts/contracts/GreetingService.sol/GreetingService.json");

  // 3) Create a simplified output that includes only what's needed
  const output = {
    ServiceFramework: {
      abi: sfArtifact.abi,
      bytecode: sfArtifact.bytecode
    },
    GreetingService: {
      abi: greetingArtifact.abi,
      bytecode: greetingArtifact.bytecode
    }
  };

  // 4) Write the file to a known location
  const outPath = path.join(__dirname, "..", "artifacts", "ExportedArtifacts.json");
  fs.writeFileSync(outPath, JSON.stringify(output, null, 2));
  console.log(`Exported artifacts to ${outPath}`);
}

// Hardhat scripts typically use this pattern:
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });


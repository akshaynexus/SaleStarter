const fs = require('fs');
const https = require('https');

// Read the package.json file
fs.readFile('package.json', 'utf8', (err, data) => {
  if (err) {
    console.error('Error reading package.json:', err);
    return;
  }

  // Parse the JSON data
  const packageJson = JSON.parse(data);
  const dependencies = packageJson.dependencies;
  const devDependencies = packageJson.devDependencies;

  // Function to update dependencies
  const updateDependencies = (dependencies, callback) => {
    // Iterate over each dependency
    for (const [package, version] of Object.entries(dependencies)) {
      // Make an HTTP request to the npm registry to get the latest version
      https.get(`https://registry.npmjs.org/${package}/latest`, (res) => {
        let latestData = '';
        res.on('data', (chunk) => {
          latestData += chunk;
        });
        res.on('end', () => {
          const latestVersion = `^${JSON.parse(latestData).version}`;
          // Compare the current version with the latest version
          if (version !== latestVersion) {
            // Update the version in the package.json file
            dependencies[package] = latestVersion;
          }
          callback();
        });
      }).on('error', (err) => {
        console.error(`Error checking latest version for package "${package}":`, err);
        callback();
      });
    }
  };

  // Update dependencies
  updateDependencies(dependencies, () => {
    // Update devDependencies
    updateDependencies(devDependencies, () => {
      // Write the updated package.json file
      fs.writeFile('package.json', JSON.stringify(packageJson, null, 2), (err) => {
        if (err) {
          console.error('Error writing package.json:', err);
        } else {
          console.log('package.json updated successfully.');
        }
      });
    });
  });
});
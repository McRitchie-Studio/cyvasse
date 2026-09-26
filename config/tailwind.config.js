// Pulls the shared studio-engine palette so the app matches the McRitchie theme
// (studio-engine/docs/NEW_APP_SETUP.md section 3).
const execSync = require('child_process').execSync
const studioPath = execSync('bundle show studio-engine').toString().trim()

const studioColors = require(`${studioPath}/tailwind/studio.tailwind.config.js`)

const shades = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900]
const utilities = ['bg', 'text', 'border']
const opacities = [5, 10, 20, 30, 40, 50]
const safelist = [
  ...utilities.map(util => `${util}-primary`),
  ...utilities.flatMap(util => opacities.map(op => `${util}-primary/${op}`)),
  ...shades.flatMap(shade => utilities.map(util => `${util}-primary-${shade}`)),
  ...shades.flatMap(shade =>
    utilities.flatMap(util => opacities.map(op => `${util}-primary-${shade}/${op}`))
  ),
]

module.exports = {
  darkMode: 'class',
  content: [
    './app/views/**/*.{erb,html}',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    // Load-bearing: engine @utility classes are emitted only when Tailwind
    // sees them used, so without this glob the engine partials render unstyled.
    `${studioPath}/app/views/**/*.{erb,html}`,
  ],
  safelist,
  theme: studioColors.theme,
}

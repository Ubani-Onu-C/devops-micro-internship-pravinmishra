# DMI Portfolio Website (Static HTML/CSS)

This repository contains a clean, professional-looking **static portfolio website** used in **DevOps Micro Internship (DMI)** Week 1 to practice:
- Linux basics
- Nginx hosting
- Deployment proof / ownership
- Production-style checks

✅ Students deploy this website on an Ubuntu VM using Nginx and keep it live for 24 hours.

---

## Who is this for?
- DMI students (beginner → intermediate)
- Anyone learning how to host a static site with Nginx on Linux

---

## What you will build
A portfolio-style website hosted on:
- **Ubuntu VM**
- **Nginx**
- Accessible via: `http://<public-ip>`

---

## Mandatory Ownership Proof (DMI Rule)
Before you deploy, you MUST edit the footer and add your details:

Original:

```html
<p>Crafted with <span>cloud</span> excellence by Pravin Mishra</p>
```

Add this line (example):

```html
<p><strong>Deployed by:</strong> DMI Cohort 2 | Rahul Sharma | Group 4 | Week 1 | 16-01-2026</p>
```

✅ This proof must be visible in your browser screenshot submission.
## Footer & Deploy Date

The site footer displays a version string, deploy date, and author name:

`Pravin Mishra Portfolio v1.0 — Deployed on <date> — By Ubani Onu Chukwu`

The deploy date is generated dynamically using JavaScript rather than hardcoded. On page load, a script sets the current date into a `<span id="deployDate">` element inside the footer, formatted as `DD Mon YYYY`:

​```javascript
const deployDate = new Date();
const options = { day: '2-digit', month: 'short', year: 'numeric' };
document.getElementById('deployDate').textContent = deployDate.toLocaleDateString('en-GB', options).replace(',', '');
​```

This means the displayed date always reflects the date the page was actually loaded/viewed, rather than requiring a manual update on every deployment.

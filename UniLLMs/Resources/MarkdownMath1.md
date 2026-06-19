# Markdown Math Rendering Torture Fixture

> Purpose: verify Markdown + KaTeX rendering for inline math, display math, physics notation, chemistry via mhchem, tables, lists, quotes, code fences, escaping, and streaming chunk boundaries.

---

## 1. Delimiter Coverage

Inline single-dollar math: $a^2 + b^2 = c^2$, $E = mc^2$, and $e^{i\pi} + 1 = 0$.

Inline escaped-parenthesis math: \( \nabla \cdot \mathbf{E} = \rho / \varepsilon_0 \), \( \alpha, \beta, \gamma, \Gamma, \Omega \).

Inline spacing edge cases: text before$x+y$after, text before $ x + y $ after, and punctuation $f'(x)=2x$.

Escaped dollars should stay text: the price is \$2.50, not math, while this is math $2.50 + x$.

Display dollar block:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

Display bracket block:

\[
\lim_{n \to \infty}\left(1 + \frac{x}{n}\right)^n = e^x
\]

Single-line display dollar block:

$$\sum_{k=1}^{n} k = \frac{n(n+1)}{2}$$

Single-line display bracket block:

\[\prod_{k=1}^{n} k = n!\]

---

## 2. Basic Math Typography

Fractions, roots, scripts, accents, and operators:

$$
\frac{\partial^2 u}{\partial t^2}
= c^2 \nabla^2 u,\qquad
\sqrt[n]{1+x},\qquad
\hat{\theta},\ \bar{x},\ \vec{v},\ \dot{x},\ \ddot{x}
$$

Sets and logic:

$$
\forall \varepsilon > 0\ \exists \delta > 0:
0 < |x-a| < \delta \Rightarrow |f(x)-L| < \varepsilon
$$

Text inside math:

$$
f(x)=
\begin{cases}
x^2, & \text{if } x \ge 0,\\
-x, & \text{if } x < 0.
\end{cases}
$$

---

## 3. Algebra, Calculus, And Analysis

Quadratic formula inline: $x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$.

Taylor expansion:

$$
f(x) = \sum_{n=0}^{\infty}
\frac{f^{(n)}(a)}{n!}(x-a)^n
$$

Fourier transform pair:

$$
\mathcal{F}\{f(t)\}(\omega)
= \int_{-\infty}^{\infty} f(t)e^{-i\omega t}\,dt,
\qquad
f(t)=\frac{1}{2\pi}\int_{-\infty}^{\infty}
\hat{f}(\omega)e^{i\omega t}\,d\omega
$$

Complex contour integral:

$$
\oint_{\partial \Omega} f(z)\,dz
= 2\pi i\sum_{z_k \in \Omega}\operatorname{Res}(f,z_k)
$$

Long expression for horizontal overflow and line wrapping:

$$
\Pr\left(\bigcup_{i=1}^{n} A_i\right)
= \sum_i \Pr(A_i)
- \sum_{i<j}\Pr(A_i\cap A_j)
+ \sum_{i<j<k}\Pr(A_i\cap A_j\cap A_k)
- \cdots
+ (-1)^{n+1}\Pr(A_1\cap\cdots\cap A_n)
$$

---

## 4. Matrices, Vectors, And Linear Algebra

Inline vector and matrix symbols: $\mathbf{x}\in\mathbb{R}^n$, $\lVert \mathbf{x}\rVert_2$, and $\mathbf{A}^{-1}\mathbf{b}$.

Matrix environments:

$$
\mathbf{A}=
\begin{bmatrix}
1 & 2 & 3\\
0 & -1 & 4\\
5 & 6 & 0
\end{bmatrix},
\qquad
\det(\mathbf{A}-\lambda\mathbf{I})=0
$$

Augmented system:

$$
\left[
\begin{array}{ccc|c}
2 & -1 & 0 & 1\\
-1 & 2 & -1 & 0\\
0 & -1 & 2 & 1
\end{array}
\right]
$$

Eigen decomposition:

$$
\mathbf{A}
= \mathbf{Q}\mathbf{\Lambda}\mathbf{Q}^{-1},
\qquad
\mathbf{\Lambda}=\operatorname{diag}(\lambda_1,\lambda_2,\ldots,\lambda_n)
$$

Norms and inner products:

$$
\left\langle u, v \right\rangle
= \int_{\Omega} u(x)\overline{v(x)}\,dx,
\qquad
\left\lVert u \right\rVert_{H^1}
= \left(\lVert u\rVert_{L^2}^2+\lVert \nabla u\rVert_{L^2}^2\right)^{1/2}
$$

---

## 5. Aligned Equations

Aligned derivation:

$$
\begin{aligned}
\frac{d}{dx}\left(x^n\right) &= n x^{n-1}\\
\frac{d}{dx}\left(e^{ax}\right) &= a e^{ax}\\
\frac{d}{dx}\left(\ln x\right) &= \frac{1}{x}
\end{aligned}
$$

Multi-line optimization with constraints:

$$
\begin{aligned}
\min_{\mathbf{x}\in\mathbb{R}^n}\quad
& \frac{1}{2}\mathbf{x}^{\mathsf T}\mathbf{Q}\mathbf{x}
+ \mathbf{c}^{\mathsf T}\mathbf{x}\\
\text{subject to}\quad
& \mathbf{A}\mathbf{x}\le \mathbf{b},\\
& \mathbf{x}\ge \mathbf{0}.
\end{aligned}
$$

Cases with nested aligned content:

$$
u(x,t)=
\begin{cases}
\displaystyle \sum_{n=1}^{\infty} b_n\sin\left(\frac{n\pi x}{L}\right)
e^{-\alpha(n\pi/L)^2 t}, & 0 < x < L,\\
0, & \text{otherwise}.
\end{cases}
$$

Equation tag:

$$
G_{\mu\nu} + \Lambda g_{\mu\nu}
= \frac{8\pi G}{c^4}T_{\mu\nu}
\tag{Einstein}
$$

---

## 6. Physics

Classical mechanics:

$$
\mathbf{F} = m\mathbf{a},\qquad
\mathbf{L}=\mathbf{r}\times\mathbf{p},\qquad
H(q,p,t)=\sum_i p_i\dot{q}_i - L(q,\dot{q},t)
$$

Lagrange equation:

$$
\frac{d}{dt}\left(\frac{\partial L}{\partial \dot{q}_i}\right)
- \frac{\partial L}{\partial q_i}=0
$$

Electromagnetism:

$$
\begin{aligned}
\nabla \cdot \mathbf{E} &= \frac{\rho}{\varepsilon_0},&
\nabla \cdot \mathbf{B} &= 0,\\
\nabla \times \mathbf{E} &= -\frac{\partial \mathbf{B}}{\partial t},&
\nabla \times \mathbf{B} &= \mu_0\mathbf{J}
+ \mu_0\varepsilon_0\frac{\partial \mathbf{E}}{\partial t}.
\end{aligned}
$$

Lorentz force inline: $\mathbf{F}=q(\mathbf{E}+\mathbf{v}\times\mathbf{B})$.

Quantum mechanics:

$$
i\hbar\frac{\partial}{\partial t}\Psi(\mathbf{r},t)
= \left[-\frac{\hbar^2}{2m}\nabla^2 + V(\mathbf{r},t)\right]\Psi(\mathbf{r},t)
$$

Commutator and uncertainty:

$$
[\hat{x},\hat{p}] = i\hbar,
\qquad
\Delta x\,\Delta p \ge \frac{\hbar}{2}
$$

Dirac notation without requiring the physics extension:

$$
\left\langle \phi \middle| \psi \right\rangle
= \int \phi^*(x)\psi(x)\,dx,
\qquad
\hat{H}\left|\psi\right\rangle = E\left|\psi\right\rangle
$$

Relativity:

$$
ds^2 = -c^2d\tau^2
= g_{\mu\nu}dx^\mu dx^\nu,
\qquad
p^\mu p_\mu = -m^2c^2
$$

Thermodynamics and statistical mechanics:

$$
Z = \sum_i e^{-\beta E_i},
\qquad
F = -k_BT\ln Z,
\qquad
dU = T\,dS - p\,dV + \mu\,dN
$$

Fluid dynamics:

$$
\rho\left(\frac{\partial \mathbf{u}}{\partial t}
+ \mathbf{u}\cdot\nabla\mathbf{u}\right)
= -\nabla p + \mu\nabla^2\mathbf{u} + \mathbf{f},
\qquad
\nabla\cdot\mathbf{u}=0
$$

---

## 7. Chemistry With mhchem

Inline formulas: water $\ce{H2O}$, sulfate $\ce{SO4^2-}$, ammonium $\ce{NH4+}$, silver chloride $\ce{AgCl}$.

Reaction with states:

$$
\ce{2 H2(g) + O2(g) -> 2 H2O(l)}
$$

Equilibrium with catalyst and heat:

$$
\ce{N2(g) + 3 H2(g) <=>[\Delta][Fe] 2 NH3(g)}
$$

Acid-base reaction:

$$
\ce{CH3COOH + H2O <=> CH3COO- + H3O+}
$$

Precipitation and solubility product:

$$
\ce{Ag+ (aq) + Cl- (aq) -> AgCl(s) v},
\qquad
K_{\mathrm{sp}}(\ce{AgCl}) = [\ce{Ag+}][\ce{Cl-}]
$$

Redox half reactions:

$$
\begin{aligned}
\ce{Fe^2+ -> Fe^3+ + e-}\\
\ce{MnO4- + 8H+ + 5e- -> Mn^2+ + 4H2O}
\end{aligned}
$$

Isotopes and nuclear equation:

$$
\ce{^{235}_{92}U + ^1_0n -> ^{141}_{56}Ba + ^{92}_{36}Kr + 3 ^1_0n}
$$

Physical units with `\pu`:

$$
g = \pu{9.80665 m.s-2},
\qquad
R = \pu{8.314462618 J.mol-1.K-1},
\qquad
c = \pu{2.99792458e8 m.s-1}
$$

Nested chemical notation inside prose: the carbonate equilibrium $\ce{CO2 + H2O <=> H2CO3 <=> H+ + HCO3-}$ should stay inline.

---

## 8. Tables, Lists, And Quotes

| Context | Inline Math | Chemistry | Expected |
| :-- | :-- | :-- | :-- |
| table cell | $\sigma^2 = E[X^2]-E[X]^2$ | $\ce{Na+ + Cl- -> NaCl}$ | inline render |
| punctuation | $(x+1)^2=x^2+2x+1$. | $\ce{H+}$, $\ce{OH-}$. | no extra spacing |
| long cell | $\displaystyle \int_0^1 x^{a-1}(1-x)^{b-1}\,dx=\frac{\Gamma(a)\Gamma(b)}{\Gamma(a+b)}$ | $\ce{C6H12O6}$ | wrap or scroll cleanly |

1. Ordered item with inline math $F_n = F_{n-1}+F_{n-2}$.
2. Ordered item with display math:

   $$
   \begin{bmatrix}
   \cos\theta & -\sin\theta\\
   \sin\theta & \cos\theta
   \end{bmatrix}
   \begin{bmatrix}x\\y\end{bmatrix}
   =
   \begin{bmatrix}
   x\cos\theta-y\sin\theta\\
   x\sin\theta+y\cos\theta
   \end{bmatrix}
   $$

3. Ordered item with chemistry $\ce{CaCO3 ->[\Delta] CaO + CO2}$.

> Blockquote inline math: $P(A\mid B)=\frac{P(B\mid A)P(A)}{P(B)}$.
>
> Blockquote display math:
>
> $$
> \nabla^2\phi = 4\pi G\rho
> $$

---

## 9. Markdown Interaction Controls

Inline code must not render as math: `$x^2$`, `\(\alpha+\beta\)`, and `\ce{H2O}`.

Code fence must stay literal:

```latex
Inline: $x^2 + y^2 = z^2$
Display:
$$
\ce{2 H2 + O2 -> 2 H2O}
$$
```

HTML code tag must stay literal: <code>$E=mc^2$</code>.

Escaped Markdown punctuation around math: \*literal asterisks\* beside $\star \ne *$.

---

## 10. Streaming Stress Cases

The next paragraph intentionally places many short inline formulas close together so random streaming chunks split delimiters often: $\alpha_1$, $\beta_2$, $\gamma_3$, $\delta_4$, $\epsilon_5$, $\zeta_6$, $\eta_7$, $\theta_8$, $\iota_9$, $\kappa_{10}$.

Adjacent formulas: $x$+$y$=$z$ and \(\sin^2 x\)+\(\cos^2 x\)=\(1\).

Mixed inline chemistry and math: $\ce{H2O}$ has molar mass $2(1.008)+15.999\approx\pu{18.015 g.mol-1}$.

Final display formula:

$$
\boxed{
\int_{\Omega} \nabla u\cdot\nabla v\,d\Omega
= \int_{\Omega} fv\,d\Omega
+ \int_{\partial\Omega_N} gv\,dS
}
$$

End marker with inline math $\omega = 2\pi f$.

! PROMPT Toolbox for MATLAB
!
! By Gaik Tamazian, 2016.
! gaik (dot) tamazian (at) gmail (dot) com

module prompt

  implicit none
  
  type :: TrModel
    real(kind=8), pointer :: r(:,:), alpha(:,:), psi(:,:)
    real(kind=8), pointer :: start_coords(:,:)
    real(kind=8), pointer :: atom_masses(:)
    real(kind=8), pointer :: rot_mat(:,:,:)
    integer(kind=4)       :: atom_num, conf_num
  end type TrModel

contains
  
  ! Procedure implementing the cross product of a pair of vectors
  function cross3d(a, b)
    real(kind=8), dimension(3) :: a, b
    real(kind=8), dimension(3) :: cross3d

    cross3d(1) = a(2)*b(3) - a(3)*b(2)
    cross3d(2) = a(3)*b(1) - a(1)*b(3)
    cross3d(3) = a(1)*b(2) - a(2)*b(1)

  end function cross3d

  function cross(a, b, n)
    integer(kind=4)               :: n
    real(kind=8), dimension(n, 3) :: a, b, cross

    integer(kind=4) :: i

    do i = 1, n
      cross(i, :) = cross3d(a(i, :), b(i, :))
    end do

  end function cross

  function dot(a, b, n)
    integer(kind=4) :: n
    real(kind=8), dimension(n, 3) :: a, b
    real(kind=8), dimension(n) :: dot

    integer(kind=4) :: i

    do i = 1, n
      dot(i) = dot_product(a(i, :), b(i, :))
    end do

  end function dot
 
  ! Procedure to restore Cartesian coordinates from internal ones
  ! for a single configuration
  subroutine restoreCoords(r, alpha, psi, atom_num, coords)
    integer(kind=4), intent(in)  :: atom_num
    real(kind=8),    intent(in)  :: r(atom_num - 1)
    real(kind=8),    intent(in)  :: alpha(atom_num -2)
    real(kind=8),    intent(in)  :: psi(atom_num - 3)
    real(kind=8),    intent(out) :: coords(atom_num, 3)

    integer(kind=4)               :: i
    real(kind=8), dimension(3)    :: bc, n
    real(kind=8), dimension(3, 3) :: M

    coords(1, :) = [0.0d0, 0.0d0, 0.0d0]
    coords(2, :) = [r(1), 0.0d0, 0.0d0]
    coords(3, :) = coords(2, :) + [r(2) * cos(alpha(1)), r(2) * &
      sin(alpha(1)), 0.0d0]

    coords(4:, 1) = r(3:) * cos(alpha(2:))
    coords(4:, 2) = r(3:) * sin(alpha(2:)) * cos(psi)
    coords(4:, 3) = r(3:) * sin(alpha(2:)) * sin(psi)

    do i = 4, atom_num
      ! calculate the bc vector
      bc = coords(i-1, :) - coords(i-2, :)
      bc = bc / sqrt(sum(bc**2))
      ! calculate the n vector
      n = cross3d(coords(i-2, :) - coords(i-3, :), bc)
      n = n / sqrt(sum(n**2))
      ! calculate the M matrix
      M(:, 1) = bc
      M(:, 2) =  cross3d(n, bc)
      M(:, 3) = n
      ! get the point coordinates
      coords(i, :) = matmul(M, coords(i, :)) + coords(i-1, :)
    end do
  
  return
  end subroutine restoreCoords

  ! Procedure to restore Cartesian coordinates for all
  ! configurations of a transformation.
  subroutine trRestoreCoords(m, coords, conf_coords)
    type(TrModel), intent(in)          :: m
    real(kind=8),  intent(out), target :: coords(m%atom_num, 3, &
      m%conf_num)
    real(kind=8),  intent(out)         :: conf_coords(m%atom_num, 3, &
      m%conf_num)

    integer(kind=4)            :: i, j
    real(kind=8), dimension(3) :: curr_trans, first_trans
    real(kind=8), pointer      :: curr_conf(:,:)

    coords(:, :, 1) = m%start_coords
    first_trans = sum(m%start_coords, 1) / m%atom_num

    do i = 2, m%conf_num
      curr_conf => coords(:, :, i)
      call restoreCoords(m%r(:, i), m%alpha(:, i), &
        m%psi(:, i), m%atom_num, curr_conf)
      conf_coords(:, :, i) = coords(:, :, i)
      ! apply the rotation and the transformation
      curr_conf = matmul(curr_conf, m%rot_mat(:, :, i))
      curr_trans = sum(curr_conf, 1) / m%atom_num
      do j = 1, m%atom_num
        curr_conf(j, :) = curr_conf(j, :) - curr_trans + &
          first_trans
      end do
    end do

  return
  end subroutine trRestoreCoords

  ! Procedure to calculate transtormation cost; note that it also
  ! returns Cartesian coordinates of configuration atoms restored from
  ! their internal coordinates
  subroutine trCost(m, p, cost_val, tr_coords, conf_coords)
    type(TrModel),   intent(in)  :: m
    integer(kind=4), intent(in)  :: p
    real(kind=8),    intent(out) :: cost_val
    real(kind=8),    intent(out) :: tr_coords(m%atom_num, 3, m%conf_num)
    real(kind=8),    intent(out) :: conf_coords(m%atom_num, 3, &
      m%conf_num)

    integer(kind=4)                     :: i
    real(kind=8), dimension(m%atom_num) :: temp_dist
    
    call trRestoreCoords(m, tr_coords, conf_coords)
      
    cost_val = 0
    do i = 1, m%conf_num - 1
      temp_dist = sqrt(sum((tr_coords(:, :, i + 1) - &
        tr_coords(:, :, i)) ** 2, 2))
      cost_val = cost_val + sum(m%atom_masses * (temp_dist ** p))
    end do

  return
  end subroutine trCost

  ! Procedure implementing the objective function
  subroutine objFunc(m, p_num, p_indices, t_num, t_indices, &
    angle_values, p, calc_grad, func_val, grad_vec)
    type(TrModel),   intent(in)                     :: m
    integer(kind=4), intent(in)                     :: p_num
    integer(kind=4), intent(in), dimension(p_num)   :: p_indices
    integer(kind=4), intent(in)                     :: t_num
    integer(kind=4), intent(in), dimension(t_num)   :: t_indices
    real(kind=8),    intent(in),  &
      dimension((p_num + t_num) * (m%conf_num - 2)) :: angle_values
    integer(kind=4), intent(in)                     :: p
    logical,         intent(in)                     :: calc_grad
    real(kind=8),    intent(out)                    :: func_val
    real(kind=8),    intent(out), &
      dimension((p_num + t_num) * (m%conf_num - 2)) :: grad_vec

    type(TrModel) :: temp_m
    integer       :: i
    real(kind=8), dimension(m%atom_num, 3, m%conf_num) :: coords
    real(kind=8), dimension(m%atom_num, 3, m%conf_num) :: conf_coords
    real(kind=8), dimension(p_num, m%conf_num - 2)     :: temp_p_angles
    real(kind=8), dimension(t_num, m%conf_num - 2)     :: temp_t_angles

    temp_m = m

    if (p_num > 0) then
      temp_p_angles = reshape( &
        angle_values(:p_num * (m%conf_num - 2)), &
        [p_num, m%conf_num - 2])
      do i = 1, p_num
        temp_m%alpha(p_indices(i), 2:(m%conf_num - 1)) = &
          temp_p_angles(i, :)
      end do
    end if

    if (t_num > 0) then
      temp_t_angles = reshape( &
        angle_values(p_num * (m%conf_num - 2) + 1:), &
        [t_num, m%conf_num - 2])
      do i = 1, t_num
        temp_m%psi(t_indices(i), 2:(m%conf_num - 1)) = &
          temp_t_angles(i, :)
      end do
    end if

    call trCost(temp_m, p, func_val, coords, conf_coords)

    if (calc_grad) then
      grad_vec = g(temp_m, p_num, p_indices, t_num, t_indices, coords, &
        conf_coords) 
    else
      grad_vec = 0
    end if
  
  return
  end subroutine objFunc

  ! The gradient of the transformation cost objective function
  function g(m, p_num, p_indices, t_num, t_indices, coords, &
    conf_coords)
    type(TrModel)                       :: m
    integer(kind=4)                     :: p_num, t_num
    integer(kind=4), dimension(p_num)   :: p_indices
    integer(kind=4), dimension(t_num)   :: t_indices
    real(kind=8),    dimension(m%atom_num, 3, m%conf_num) :: coords
    real(kind=8),    dimension(m%atom_num, 3, m%conf_num) :: conf_coords
    real(kind=8),    dimension((p_num + t_num) * (m%conf_num - 2)) :: g

    integer(kind=4) :: i, j, angle_num
    real(kind=8), dimension(m%atom_num, 3, m%conf_num) :: vS
    real(kind=8), dimension(m%atom_num - 1, 3, m%conf_num) :: vR
    real(kind=8), dimension(m%atom_num - 2, 3, m%conf_num) :: vN, vP
    real(kind=8), dimension(m%atom_num, 3, m%atom_num - 1) :: vQ, &
      maskP, maskT, vQP, vQT
    real(kind=8), dimension(m%atom_num, 3) :: mean_vQP, mean_vQT, v
    real(kind=8), dimension(p_num + t_num, m%conf_num - 2) :: temp_g

    temp_g = 0
    vS = s(coords, m%atom_num, m%conf_num)
    vR = r(conf_coords, m%atom_num, m%conf_num)
    vN = n(vR, m%atom_num, m%conf_num)
    vP = p(vR, m%atom_num, m%conf_num)
    maskP = mask_p(m%atom_num)
    maskT = mask_t(m%atom_num)

    do j = 2, m%conf_num - 1
      vQ = q(conf_coords(:, :, j), m%atom_num)

      vQP = vQ * maskP
      vQT = vQ * maskT

      do angle_num = 1, p_num
        i = p_indices(angle_num)
        mean_vQP = spread(sum(vQP(:, :, i) , 1) / m%atom_num, &
          1, m%atom_num)
        v = cross(spread(vP(i, :, j), 1, m%atom_num), vQP(:, :, i) - &
          mean_vQP, m%atom_num)
        temp_g(angle_num, j - 1) = 2 * sum(m%atom_masses * &
          dot(vS(:, :, j), matmul(v, m%rot_mat(:, :, j)), m%atom_num))
      end do

      do angle_num = 1, t_num
        i = t_indices(angle_num)
        mean_vQT = spread(sum(vQT(:, :, i) , 1) / m%atom_num, &
          1, m%atom_num)
        v = cross(spread(vN(i, :, j), 1, m%atom_num), vQT(:, :, i) - &
          mean_vQT, m%atom_num)
        temp_g(p_num + angle_num, j - 1) = 2 * sum(m%atom_masses * &
          dot(vS(:, :, j), matmul(v, m%rot_mat(:, :, j)), m%atom_num))
      end do
    end do

    g = reshape(temp_g, [(p_num + t_num) * (m%conf_num - 2)])

  end function g 

  function r(x, atom_num, conf_num)
    integer(kind=4) :: atom_num, conf_num
    real(kind=8), dimension(atom_num, 3, conf_num)     :: x
    real(kind=8), dimension(atom_num - 1, 3, conf_num) :: r

    r = x(2:atom_num, :, :) - x(1:(atom_num - 1), :, :)

  end function r

  function n(r, atom_num, conf_num)
    integer(kind=4) :: atom_num, conf_num
    real(kind=8), dimension(atom_num - 1, 3, conf_num) :: r
    real(kind=8), dimension(atom_num - 1, 3, conf_num) :: temp_n
    real(kind=8), dimension(atom_num - 2, 3, conf_num) :: n

    temp_n = r / spread(sqrt(sum(r**2, 2)), 2, 3)
    n = temp_n(2:, :, :) 

  end function n

  function p(r, atom_num, conf_num)
    integer(kind=4) :: atom_num, conf_num
    real(kind=8), dimension(atom_num - 1, 3, conf_num) :: r
    real(kind=8), dimension(atom_num - 2, 3, conf_num) :: p

    integer(kind=4) :: i, j

    do i = 1, atom_num - 2
      do j = 1, conf_num
        p(i, :, j) = cross3d(r(i, :, j), r(i + 1, :, j)) 
        p(i, :, j) = p(i, :, j) / sqrt(sum(p(i, :, j) ** 2))
      end do
    end do

  end function p

  function s(x, atom_num, conf_num)
    integer(kind=4) :: atom_num, conf_num
    real(kind=8), dimension(atom_num, 3, conf_num) :: x
    real(kind=8), dimension(atom_num, 3, conf_num) :: s

    s(:, :, 2:(conf_num - 1)) = 2*x(:, :, 2:(conf_num - 1)) - &
      x(:, :, :(conf_num - 2)) - x(:, :, 3:)

  end function s

  function mask_p(atom_num)
    integer(kind=4) :: atom_num
    real(kind=8), dimension(atom_num, 3, atom_num - 1) :: mask_p 
    
    integer(kind=4) :: l, i

    mask_p = 0
    do i = 1, atom_num - 1
      do l = i + 2, atom_num 
        mask_p(l, :, i) = 1
      end do
    end do

  end function mask_p

  function mask_t(atom_num)
    integer(kind=4) :: atom_num
    real(kind=8), dimension(atom_num, 3, atom_num - 1) :: mask_t 
    
    integer(kind=4) :: l, i

    mask_t = 0
    do i = 1, atom_num - 1
      do l = i + 3, atom_num
        mask_t(l, :, i) = 1
      end do
    end do

  end function mask_t


  function q(conf_x, atom_num)
    integer(kind=4) :: atom_num
    real(kind=8), dimension(atom_num, 3)               :: conf_x
    real(kind=8), dimension(atom_num, 3, atom_num - 1) :: q
    
    q = spread(conf_x, 3, atom_num - 1) - &
      reshape(spread(conf_x(2:, :), 1, atom_num), &
      [atom_num, 3, atom_num - 1], ORDER=[1, 3, 2])

  end function q

end module prompt

